import AppKit
import DeduperCore
import DeviceMediaKit
import Foundation
import ImageCaptureCore

@MainActor
final class MediaBrowserViewModel: ObservableObject {
    struct MediaItem: Identifiable, @unchecked Sendable {
        let model: DeviceMediaFile
        let cameraFile: ICCameraFile
        var id: String { model.id }
    }

    private struct ScanPayload: @unchecked Sendable {
        let deviceName: String
        let items: [MediaItem]
        let plan: DuplicatePlan
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: String { rawValue }
    }

    @Published var deviceName = "No Device"
    /// `didSet` rather than bumping at each call site, so a future mutation cannot forget
    /// to invalidate the derived catalog and silently serve a stale snapshot.
    @Published var allItems: [MediaItem] = [] {
        didSet { catalogVersion &+= 1 }
    }

    /// Phase 1: focus and action selection live in one deterministic, unit-tested model.
    /// Views keep reading `selectedItemID` / `selectedActionIDs`, which now project it.
    @Published private(set) var selection = MediaSelectionState()

    var selectedItemID: String? {
        get { selection.focusedID }
        set {
            if let newValue {
                selection.focus(newValue)
            } else {
                selection.focusedID = nil
                selection.anchorID = nil
            }
        }
    }

    var selectedActionIDs: Set<String> {
        selection.actionSelectedIDs
    }

    /// Set when a renderer asks for the destructive confirmation sheet. The delete itself
    /// still only runs from the confirmed action, never from this flag.
    @Published var isConfirmingDelete = false

    /// Actionable guidance for the most recent device failure, or `nil` when the last
    /// operation succeeded. Drives the recovery banner.
    @Published var recoveryAdvice: DeviceRecoveryAdvice?

    func dismissRecoveryAdvice() {
        recoveryAdvice = nil
    }

    /// Set by the List renderer so a header click persists the new sort descriptor.
    var onSortChanged: ((MediaSortField, DeduperCore.SortOrder) -> Void)?

    @Published var reviewScope: MediaReviewScope = .allMedia
    /// What the user has typed. Bound directly to the search field so typing always feels
    /// immediate.
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearchApply()
        }
    }

    /// The query the catalog is actually filtered by. Trails `searchText` by the debounce
    /// interval so a 4,000-item derivation does not run on every keystroke.
    @Published private(set) var appliedSearchText = ""

    /// How long typing must pause before the query is applied.
    static let searchDebounceInterval: Duration = .milliseconds(180)

    private var searchDebounceTask: Task<Void, Never>?

    private func scheduleSearchApply() {
        // Cancelling supersedes the previous pending query rather than queueing another.
        searchDebounceTask?.cancel()
        let pending = searchText
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounceInterval)
            guard !Task.isCancelled, let self, self.searchText == pending else { return }
            self.applySearchText(pending)
        }
    }

    /// Applies the pending query immediately, for tests and for anything that must not wait
    /// for the debounce (a scan publishing a new catalog, for example).
    func applySearchText(_ text: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        guard appliedSearchText != text else { return }
        appliedSearchText = text
        refreshVisibleOrder()
    }

    func flushPendingSearch() {
        applySearchText(searchText)
    }
    @Published var sortField: MediaSortField = .timestamp
    @Published var sortOrder: DeduperCore.SortOrder = .descending
    @Published private(set) var viewMode: ViewMode = .list

    /// Switches renderer and starts that renderer with clean interaction state.
    ///
    /// List focus is row-oriented and Grid focus is two-dimensional, so carrying focus,
    /// anchor, and action selection across the switch produced selections the user had not
    /// made in the renderer they were looking at.
    func setViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        selection = MediaSelectionState()
        refreshVisibleOrder()
    }
    @Published var isInspectorVisible = false
    @Published var displayScale = MediaDisplayScale(rawValue: 1.0)
    @Published var status = "Connect and unlock your iPhone, then scan."
    /// One admission gate for every device operation. Replaces the old `isScanning` flag,
    /// which guarded only scan and left import and delete able to overlap each other.
    @Published private(set) var operationState = DeviceOperationState()
    @Published private(set) var operationProgress: MediaOperationProgress?
    private var operationCancellation: DeviceOperationCancellation?

    /// Kept as a projection so existing views and tests read unchanged.
    var isScanning: Bool { operationState.current == .scanning }

    /// True while any device operation owns the state machine.
    var isDeviceBusy: Bool { operationState.isBusy }

    /// Claims the operation gate without touching the device, so tests can prove that a
    /// second operation is rejected while one is in flight.
    @discardableResult
    func beginOperationForTesting(_ operation: DeviceOperationState.Operation) -> Bool {
        operationState.begin(operation)
    }

    func finishOperationForTesting() {
        operationState.finish()
    }
    @Published var thumbnailCache: [String: NSImage] = [:]
    @Published var metadataCache: [String: MediaMetadataSummary] = [:]
    @Published var importedItemIDs: Set<String> = []
    @Published var duplicatePlan = DuplicatePlan(keep: [], delete: []) {
        didSet { catalogVersion &+= 1 }
    }
    @Published var importDestination = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    @Published var lastImportedFileURL: URL?

    /// Bounded, cancellable admission for per-item device work. Replaces the unbounded
    /// in-flight sets, which let a fast scroll queue hundreds of uncancellable requests.
    private let thumbnailRequests = MediaRequestQueue(maxConcurrent: 6)
    private let metadataRequests = MediaRequestQueue(maxConcurrent: 3)
    private var thumbnailAccessOrder: [String] = []
    private let maxCachedThumbnails = 512

    /// Memory ceiling for cached thumbnails, in bytes.
    ///
    /// A count-only limit does not bound memory: 512 large thumbnails is a very different
    /// footprint from 512 small ones. Both limits apply, whichever binds first.
    private let maxThumbnailCacheBytes = 192 * 1_024 * 1_024
    private var thumbnailCacheBytes = 0
    private var thumbnailCostByID: [String: Int] = [:]
    private var metadataAccessOrder: [String] = []
    private let maxCachedMetadataSummaries = 768

    /// Publishes the current filtered order into the selection model so focus, anchor,
    /// and action selection are reconciled exactly once per state change instead of
    /// drifting behind search, sort, scope, scan, import, or delete.
    func refreshVisibleOrder() {
        selection.setVisibleIDs(visibleItems.map(\.id))
    }

    // MARK: - Derived catalog

    /// Inputs that change what the browser shows.
    ///
    /// This must stay cheap to compute: it is checked on every read, so building arrays
    /// here would cost as much as the derivation it avoids. `catalogVersion` stands in for
    /// the item list, and is bumped whenever `allItems` or the duplicate plan changes.
    private struct CatalogKey: Equatable {
        let catalogVersion: Int
        let scope: MediaReviewScope
        let searchText: String
        let sortField: MediaSortField
        let sortOrder: DeduperCore.SortOrder
    }

    private var cachedCatalogKey: CatalogKey?
    private var cachedVisibleItems: [MediaItem] = []
    private var cachedItemIndexByID: [String: Int] = [:]

    /// Bumped by every mutation of `allItems` or `duplicatePlan`.
    private var catalogVersion = 0

    /// How many times the catalog has actually been derived. Test-only instrumentation
    /// that keeps the caching guarantee honest.
    private(set) var catalogDerivationCount = 0

    private var currentCatalogKey: CatalogKey {
        CatalogKey(
            catalogVersion: catalogVersion,
            scope: reviewScope,
            searchText: appliedSearchText,
            sortField: sortField,
            sortOrder: sortOrder
        )
    }

    /// The filtered, searched, and sorted catalog the browser is showing.
    ///
    /// Derived at most once per state change. Every renderer, the status bar, and the
    /// selection model read this same snapshot.
    var visibleItems: [MediaItem] {
        let key = currentCatalogKey
        if cachedCatalogKey == key {
            return cachedVisibleItems
        }
        deriveVisibleItems(key: key)
        return cachedVisibleItems
    }

    /// Kept as the previous name so call sites and tests reading `filteredItems` continue
    /// to work; it is now the cached snapshot rather than a fresh derivation.
    var filteredItems: [MediaItem] { visibleItems }

    private func deriveVisibleItems(key: CatalogKey) {
        catalogDerivationCount += 1

        let scopedModels = reviewScope.apply(to: allItems.map(\.model), duplicatePlan: duplicatePlan)
        let scopedIDs = Set(scopedModels.map(\.id))
        let smartSearch = MediaSearchQuery(appliedSearchText)
        let searchedItems = allItems.filter { scopedIDs.contains($0.id) && smartSearch.matches($0.model) }
        let query = MediaQuery(
            filters: [],
            sort: MediaSortDescriptor(field: sortField, order: sortOrder)
        )
        let filteredModels = query.apply(to: searchedItems.map(\.model))
        let itemByID = Dictionary(uniqueKeysWithValues: searchedItems.map { ($0.id, $0) })

        var items: [MediaItem] = []
        var indexByID: [String: Int] = [:]
        items.reserveCapacity(filteredModels.count)
        indexByID.reserveCapacity(filteredModels.count)
        for model in filteredModels {
            guard let item = itemByID[model.id] else { continue }
            indexByID[item.id] = items.count
            items.append(item)
        }

        cachedVisibleItems = items
        cachedItemIndexByID = indexByID
        cachedCatalogKey = key
    }

    /// O(1) lookup instead of a linear scan through the visible catalog.
    var selectedItem: MediaItem? {
        guard let selectedItemID else { return nil }
        let items = visibleItems
        guard let index = cachedItemIndexByID[selectedItemID], items.indices.contains(index) else {
            return nil
        }
        return items[index]
    }

    var duplicateDeleteIDs: Set<String> {
        Set(duplicatePlan.delete.map(\.id))
    }

    var duplicateBytes: Int64 {
        duplicatePlan.delete.reduce(0) { $0 + $1.size }
    }

    var selectedActionItems: [MediaItem] {
        allItems.filter { selectedActionIDs.contains($0.id) }
    }

    var selectedActionBytes: Int64 {
        selectedActionItems.reduce(0) { $0 + $1.model.size }
    }

    func scan() {
        guard operationState.begin(.scanning) else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        let generation = operationState.generation
        status = "Scanning connected iPhone..."
        fputs("ui-scan-started\n", stderr)
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try Self.scanDevice(timeoutSeconds: 180)
                }.value
                // A newer scan may have started while this one was running.
                guard self.operationState.isCurrent(generation: generation) else { return }
                self.applyScanPayload(payload)
            } catch {
                guard self.operationState.isCurrent(generation: generation) else { return }
                let advice = DeviceRecoveryAdvice.forFailure("\(error)")
                self.recoveryAdvice = advice
                self.status = advice.title
                fputs("ui-scan-failed: \(error)\n", stderr)
                self.operationState.fail()
            }
        }
    }

    func select(_ item: MediaItem) {
        refreshVisibleOrder()
        selection.focus(item.id)
        isInspectorVisible = true
        loadThumbnails(for: [item])
        loadMetadata(for: item)
    }

    /// Focus by ID, used by native renderers that work in rows/indexes rather than items.
    func selectItem(withID id: String) {
        guard let item = allItems.first(where: { $0.id == id }) else { return }
        select(item)
    }

    /// Shift-click: extends the action selection from the stable anchor.
    func extendSelection(to id: String) {
        refreshVisibleOrder()
        selection.extendSelection(to: id)
    }

    func beginDragSelection(at id: String) {
        refreshVisibleOrder()
        selection.beginDragSelection(at: id)
    }

    func updateDragSelection(to id: String) {
        selection.updateDragSelection(to: id)
    }

    /// Starts a Grid marquee from blank canvas.
    func beginMarqueeSelection(additive: Bool, deselecting: Bool = false) {
        refreshVisibleOrder()
        selection.beginMarqueeSelection(additive: additive, deselecting: deselecting)
    }

    /// Starts a Grid marquee from a tile, mirroring List's start-item select/deselect rule.
    func beginMarqueeSelection(startingAt id: String) {
        refreshVisibleOrder()
        selection.beginMarqueeSelection(startingAt: id)
    }

    func updateMarqueeSelection(intersecting ids: Set<String>) {
        selection.updateMarqueeSelection(intersecting: ids)
    }

    func endDragSelection() {
        selection.endDragSelection()
    }

    /// Arrow-key focus movement. Returns the ID the renderer should scroll into view.
    @discardableResult
    func moveFocus(by offset: Int, extendingSelection: Bool) -> String? {
        refreshVisibleOrder()
        return selection.moveFocus(by: offset, extendingSelection: extendingSelection)
    }

    /// Grid arrow movement using the renderer's measured column count.
    @discardableResult
    func moveFocus(rows: Int, columns: Int, columnCount: Int, extendingSelection: Bool) -> String? {
        refreshVisibleOrder()
        return selection.moveFocus(
            rows: rows,
            columns: columns,
            columnCount: columnCount,
            extendingSelection: extendingSelection
        )
    }

    /// Space toggles the focused item in the action selection.
    @discardableResult
    func toggleFocusedItem() -> Bool {
        selection.toggleFocusedItem()
    }

    func setFocusOwner(_ owner: MediaSelectionState.FocusOwner) {
        selection.focusOwner = owner
    }

    func toggleInspector() {
        isInspectorVisible.toggle()
    }

    func toggleActionSelection(_ item: MediaItem) {
        refreshVisibleOrder()
        selection.toggleActionSelection(item.id)
    }

    /// Toggle by ID, for native renderers that work in rows/indexes rather than items.
    func toggleActionSelection(withID id: String) {
        refreshVisibleOrder()
        selection.toggleActionSelection(id)
    }

    func prepareContextActionSelection(for item: MediaItem) {
        refreshVisibleOrder()
        if !selection.actionSelectedIDs.contains(item.id) {
            selection.actionSelectedIDs = [item.id]
            selection.anchorID = item.id
        }
    }

    func selectAllVisible() {
        refreshVisibleOrder()
        // Deliberately does not force focus ownership. Command-A while the search field is
        // editing belongs to that text, not to the media browser.
        selection.selectAllVisible()
    }

    func clearActionSelection() {
        selection.actionSelectedIDs.removeAll()
    }

    /// Escape: clears focus and action selection. Inspector visibility is independent
    /// and deliberately left alone.
    @discardableResult
    func clearSelection() -> Bool {
        selection.clearSelection()
    }

    func toggleSort(_ field: MediaSortField) {
        if sortField == field {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortField = field
            sortOrder = .ascending
        }
        refreshVisibleOrder()
        onSortChanged?(sortField, sortOrder)
    }

    /// Applies a sort without notifying the persistence hook. Used when restoring a
    /// previously saved descriptor at launch, so restoring does not re-save.
    func applySort(field: MediaSortField, order: DeduperCore.SortOrder) {
        sortField = field
        sortOrder = order
        refreshVisibleOrder()
    }

    func importSelected() {
        let items = selectedActionItems
        guard !items.isEmpty else {
            status = "Select one or more items to import."
            return
        }
        // Previously unguarded: a second Import, or an Import during a Delete, would both
        // reach the device concurrently.
        guard operationState.begin(.importing) else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        let cancellation = DeviceOperationCancellation()
        operationCancellation = cancellation
        operationProgress = MediaOperationProgress(kind: .importing, totalItems: items.count)
        status = "Importing \(items.count) item(s)..."
        Task.detached(priority: .userInitiated) { [weak self, destination = importDestination] in
            guard let self else { return }
            let summary = DeviceImportController(timeoutSeconds: 120).importFiles(
                items.map(\.cameraFile),
                to: destination,
                cancellation: cancellation,
                onProgress: { update in
                    Task { @MainActor [weak self] in
                        self?.applyOperationProgress(update, for: .importing)
                    }
                }
            )
            await self.applyImportSummary(summary, destination: destination, requestedItems: items)
        }
    }

    func deleteSelected() {
        let items = selectedActionItems
        guard !items.isEmpty else {
            status = "Select one or more items to delete."
            return
        }
        // Destructive and previously unguarded, so a double-click on the confirmation
        // could submit the same delete twice.
        guard operationState.begin(.deleting) else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        let cancellation = DeviceOperationCancellation()
        operationCancellation = cancellation
        operationProgress = MediaOperationProgress(kind: .deleting, totalItems: items.count)
        status = "Deleting \(items.count) item(s)..."
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard let device = items.first?.cameraFile.device else {
                await self.applyDeleteFailure("No device available for selected files.")
                return
            }
            do {
                let summary = try DeviceSessionController(timeoutSeconds: 120).delete(
                    items.map(\.cameraFile),
                    from: device,
                    confirmed: true,
                    cancellation: cancellation,
                    onProgress: { update in
                        Task { @MainActor [weak self] in
                            self?.applyOperationProgress(update, for: .deleting)
                        }
                    }
                )
                await self.applyDeleteSummary(summary, requestedIDs: Set(items.map(\.id)))
            } catch {
                await self.applyDeleteFailure("\(error)")
            }
        }
    }

    func cancelCurrentOperation() {
        guard var progress = operationProgress,
              progress.requestCancellation() else {
            return
        }
        operationProgress = progress
        status = progress.detail
        _ = operationCancellation?.cancel()
    }

    /// Requests the destructive confirmation sheet. Does not delete anything.
    func requestDeleteConfirmation() {
        guard !selectedActionIDs.isEmpty else {
            status = "Select one or more items to delete."
            return
        }
        isConfirmingDelete = true
    }

    func revealLastImportInFinder() {
        guard let lastImportedFileURL else {
            status = "No imported file to reveal yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([lastImportedFileURL])
    }

    func selectReviewScope(_ scope: MediaReviewScope) {
        reviewScope = scope
        refreshVisibleOrder()
    }

    func loadThumbnails(for items: [MediaItem]) {
        let candidates = items.filter { thumbnailCache[$0.id] == nil }
        guard !candidates.isEmpty else {
            return
        }
        // Admission is bounded, so a burst of newly visible rows cannot flood the device.
        // Rows refused here are re-requested the next time they appear.
        let missing = candidates.filter { thumbnailRequests.beginIfAllowed($0.id) }
        guard !missing.isEmpty else {
            return
        }
        let generation = operationState.generation

        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            var loaded: [(id: String, image: NSImage)] = []
            for item in missing {
                guard let image = ThumbnailProvider.thumbnail(for: item.cameraFile, timeoutSeconds: 6) else {
                    continue
                }
                loaded.append((id: item.id, image: image))
            }
            guard !loaded.isEmpty else {
                await self.finishThumbnailRequests(ids: missing.map(\.id), generation: generation)
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self.cacheThumbnails(loaded, completedIDs: missing.map(\.id), generation: generation)
        }
    }

    func setDisplayScale(_ rawValue: Double) {
        displayScale = MediaDisplayScale(rawValue: rawValue)
    }

    func metadataSummary(for item: MediaItem) -> MediaMetadataSummary? {
        metadataCache[item.id]
    }

    func loadVisibleDetails(for item: MediaItem) {
        loadThumbnails(for: [item])
        loadMetadata(for: item)
    }

    nonisolated private static func scanDevice(timeoutSeconds: TimeInterval) throws -> ScanPayload {
        let result = try DeviceSessionController(timeoutSeconds: timeoutSeconds).scan()
        let items = result.files.map { MediaItem(model: $0.model, cameraFile: $0.cameraFile) }
        let plan = DuplicatePlanner.plan(files: items.map(\.model), rule: .nameKindSize)
        return ScanPayload(deviceName: result.deviceName, items: items, plan: plan)
    }

    private func applyScanPayload(_ payload: ScanPayload) {
        deviceName = payload.deviceName
        allItems = payload.items
        duplicatePlan = payload.plan
        selection = MediaSelectionState()
        // The previous session's outstanding requests are meaningless now.
        thumbnailRequests.cancelAll()
        metadataRequests.cancelAll()
        // A scan can land while the user is mid-word. Applying the pending query now keeps
        // the visible field and the filtered catalog in agreement, instead of showing an
        // unfiltered list under a non-empty search box until the debounce fires.
        flushPendingSearch()
        refreshVisibleOrder()
        importedItemIDs.removeAll()
        recoveryAdvice = nil
        status = "Scanned \(payload.items.count) items. Conservative duplicates: \(payload.plan.delete.count)."
        fputs("ui-scan-succeeded: scanned=\(payload.items.count) duplicates=\(payload.plan.delete.count)\n", stderr)
        operationState.finish()
        Task { @MainActor [weak self, items = payload.items] in
            await Task.yield()
            self?.loadThumbnails(for: Array(items.prefix(96)))
        }
    }

    /// Drops results whose scan session has been superseded. Without this, a slow
    /// thumbnail from a previous scan could land in the new session's cache under an ID
    /// that now means a different file.
    private func cacheThumbnails(
        _ images: [(id: String, image: NSImage)],
        completedIDs: [String],
        generation: Int
    ) {
        guard operationState.isCurrent(generation: generation) else { return }
        for image in images {
            if let previousCost = thumbnailCostByID[image.id] {
                thumbnailCacheBytes -= previousCost
            }
            let cost = Self.thumbnailCost(of: image.image)
            thumbnailCostByID[image.id] = cost
            thumbnailCacheBytes += cost

            thumbnailCache[image.id] = image.image
            thumbnailAccessOrder.removeAll { $0 == image.id }
            thumbnailAccessOrder.append(image.id)
        }
        finishThumbnailRequests(ids: completedIDs, generation: generation)
        trimThumbnailCacheIfNeeded()
    }

    private func finishThumbnailRequests(ids: [String], generation: Int) {
        // Slots are released regardless of generation; otherwise a superseded scan would
        // leak them and the queue would starve.
        for id in ids {
            thumbnailRequests.finish(id)
        }
    }

    /// Evicts least-recently-used thumbnails until both the count and the memory-cost
    /// limits are satisfied.
    private func trimThumbnailCacheIfNeeded() {
        while thumbnailAccessOrder.count > maxCachedThumbnails
            || (thumbnailCacheBytes > maxThumbnailCacheBytes && !thumbnailAccessOrder.isEmpty) {
            let id = thumbnailAccessOrder.removeFirst()
            thumbnailCache.removeValue(forKey: id)
            thumbnailCacheBytes -= thumbnailCostByID.removeValue(forKey: id) ?? 0
        }
        thumbnailCacheBytes = max(0, thumbnailCacheBytes)
    }

    /// Approximate decoded size of an image, used as its cache cost.
    nonisolated static func thumbnailCost(of image: NSImage) -> Int {
        guard let representation = image.representations.first else { return 0 }
        // 4 bytes per pixel is the usual decoded footprint for these previews.
        return representation.pixelsWide * representation.pixelsHigh * 4
    }

    private func loadMetadata(for item: MediaItem) {
        guard metadataCache[item.id] == nil,
              metadataRequests.beginIfAllowed(item.id) else {
            return
        }
        let generation = operationState.generation
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            let summary = MetadataProvider.summary(for: item.cameraFile, timeoutSeconds: 30)
            await self.cacheMetadata(summary, id: item.id, generation: generation)
        }
    }

    private func cacheMetadata(_ summary: MediaMetadataSummary?, id: String, generation: Int) {
        metadataRequests.finish(id)
        guard operationState.isCurrent(generation: generation) else { return }
        guard let summary else {
            return
        }
        metadataCache[id] = summary
        metadataAccessOrder.removeAll { $0 == id }
        metadataAccessOrder.append(id)
        trimMetadataCacheIfNeeded()
    }

    private func applyImportSummary(_ summary: DeviceImportSummary, destination: URL, requestedItems: [MediaItem]) {
        if let filename = summary.successful.last?.filename {
            lastImportedFileURL = destination.appendingPathComponent(filename)
        }
        let successfulHandles = Set(summary.successful.map(\.file.ptpObjectHandle))
        let successfulIDs = requestedItems
            .filter { successfulHandles.contains($0.cameraFile.ptpObjectHandle) }
            .map(\.id)
        importedItemIDs.formUnion(successfulIDs)
        status = "Imported \(summary.successful.count) item(s), \(summary.failed.count) failed, \(summary.canceled.count) canceled."
        operationProgress = nil
        operationCancellation = nil
        operationState.finish()
    }

    private func applyDeleteSummary(_ summary: DeviceDeleteSummary, requestedIDs: Set<String>) {
        let successfulHandles = Set(summary.successful.map(\.ptpObjectHandle))
        allItems.removeAll { item in
            requestedIDs.contains(item.id) && successfulHandles.contains(item.cameraFile.ptpObjectHandle)
        }
        duplicatePlan = DuplicatePlanner.plan(files: allItems.map(\.model), rule: .nameKindSize)
        refreshVisibleOrder()
        status = "Deleted \(summary.successful.count) item(s), \(summary.failed.count) failed, \(summary.canceled.count) canceled."
        operationProgress = nil
        operationCancellation = nil
        operationState.finish()
    }

    private func applyDeleteFailure(_ message: String) {
        let advice = DeviceRecoveryAdvice.forFailure(message)
        recoveryAdvice = advice
        status = "Delete failed: \(advice.title)"
        operationProgress = nil
        operationCancellation = nil
        operationState.fail()
    }

    private func applyOperationProgress(
        _ update: DeviceBatchProgress,
        for operation: DeviceOperationState.Operation
    ) {
        guard operationState.current == operation,
              var progress = operationProgress else {
            return
        }
        progress.apply(update)
        operationProgress = progress
        status = progress.detail
    }

    private func trimMetadataCacheIfNeeded() {
        while metadataAccessOrder.count > maxCachedMetadataSummaries {
            let id = metadataAccessOrder.removeFirst()
            metadataCache.removeValue(forKey: id)
        }
    }
}
