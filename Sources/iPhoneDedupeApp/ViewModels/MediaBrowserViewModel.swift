import AppKit
import DeduperCore
import DeviceMediaKit
import Foundation

@MainActor
final class MediaBrowserViewModel: ObservableObject {
    struct MediaItem: Identifiable, Sendable {
        let model: DeviceMediaFile
        let token: DeviceFileToken
        var id: String { model.id }
    }

    private struct ScanPayload: Sendable {
        let deviceName: String
        let deviceIdentityHash: String?
        let items: [MediaItem]
        let plan: DuplicatePlan
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: String { rawValue }
    }

    @Published var deviceName = "No Device"
    private var deviceIdentityHash: String?
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
    @Published private(set) var pendingDeleteSnapshot: DeletePlanSnapshot?

    /// Actionable guidance for the most recent device failure, or `nil` when the last
    /// operation succeeded. Drives the recovery banner.
    @Published var recoveryAdvice: DeviceRecoveryAdvice?

    @Published private(set) var operationHistory: [OperationResultRecord] = []
    @Published private(set) var operationHistoryWarning: String?
    @Published var isShowingOperationHistory = false
    private let operationResultStore: OperationResultStore
    typealias ImportPreflight = (URL, [ImportDestinationPreflight.Item]) -> ImportDestinationPreflight.Outcome

    /// The catalog rescan that verifies a delete. Injectable so the verification phase and
    /// its cancellation can be tested without a device.
    typealias VerificationScan = @MainActor (Duration) async throws -> DeviceCatalogSnapshot
    typealias InspectorPreviewRequest = (
        DeviceFileToken,
        Int,
        @escaping @Sendable (NSImage?) -> Void
    ) -> Void
    private let gateway: ImageCaptureDeviceGateway
    private let stagingManager: ImportStagingManager
    private let importPreflight: ImportPreflight
    private let inspectorPreviewRequest: InspectorPreviewRequest
    private let inspectorPreviewTimeout: Duration
    private let verificationScan: VerificationScan

    /// Test-only instrumentation proving Retry Verification never resubmits a delete.
    private(set) var deleteSubmissionCountForTesting = 0

    init(
        operationResultStore: OperationResultStore = .applicationSupport(),
        gateway: ImageCaptureDeviceGateway? = nil,
        stagingManager: ImportStagingManager = .applicationCaches(),
        importPreflight: @escaping ImportPreflight = { destination, items in
            ImportDestinationPreflight.inspect(destination: destination, items: items)
        },
        inspectorPreviewTimeout: Duration = .seconds(12),
        inspectorPreviewRequest: InspectorPreviewRequest? = nil,
        verificationScan: VerificationScan? = nil
    ) {
        let resolvedGateway = gateway ?? ImageCaptureDeviceGateway()
        self.gateway = resolvedGateway
        self.stagingManager = stagingManager
        self.operationResultStore = operationResultStore
        self.importPreflight = importPreflight
        self.inspectorPreviewTimeout = inspectorPreviewTimeout
        self.verificationScan = verificationScan ?? { timeout in
            try await resolvedGateway.scan(timeout: timeout)
        }
        self.inspectorPreviewRequest = inspectorPreviewRequest ?? { token, maxPixelSize, completion in
            Task { @MainActor in
                let image: NSImage?
                do {
                    let data = try await resolvedGateway.thumbnailData(
                        for: token,
                        maxPixelSize: maxPixelSize,
                        timeout: .seconds(12)
                    )
                    image = InspectorPreviewProvider.decode(data, maxPixelSize: maxPixelSize)
                } catch {
                    image = nil
                }
                completion(image)
            }
        }
        try? stagingManager.cleanupStaleSessions()
        let loaded = operationResultStore.load()
        operationHistory = loaded.records
        operationHistoryWarning = loaded.warning
    }

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
    @Published private(set) var inspectorPreviewCache: [String: NSImage] = [:]
    @Published var importedItemIDs: Set<String> = []
    private var importedFileURLsByItemID: [String: URL] = [:]
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

    private static let inspectorPreviewCountLimit = 8
    private static let inspectorPreviewCostLimit = 96 * 1_024 * 1_024
    private var inspectorPreviewAccessOrder: [String] = []
    private var inspectorPreviewCostByID: [String: Int] = [:]
    private var inspectorPreviewTotalCost = 0
    private var inspectorPreviewSelectedID: String?
    private var inspectorPreviewDesiredItem: MediaItem?
    private var inspectorPreviewFailedSelectionID: String?
    private var inspectorPreviewActive: (token: UUID, item: MediaItem, generation: Int)?
    private var inspectorPreviewTimeoutTask: Task<Void, Never>?

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
                let snapshot = try await self.gateway.scan(timeout: .seconds(180))
                let items = snapshot.files.map { MediaItem(model: $0.model, token: $0.token) }
                let payload = ScanPayload(
                    deviceName: snapshot.deviceName,
                    deviceIdentityHash: snapshot.deviceIdentityHash,
                    items: items,
                    plan: DuplicatePlanner.plan(files: items.map(\.model), rule: .nameKindSize)
                )
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
        guard !operationState.isBusy else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        let preflightItems = items.map {
            ImportDestinationPreflight.Item(filename: $0.model.name, size: $0.model.size)
        }
        if case let .blocked(failure) = importPreflight(importDestination, preflightItems) {
            status = "Import blocked: \(failure.message)"
            return
        }
        let destinationIdentity: ImportDestinationIdentity
        do {
            destinationIdentity = try ImportDestinationIdentity.capture(destination: importDestination)
        } catch {
            status = "Import blocked: \(error.localizedDescription)"
            return
        }
        // Previously unguarded: a second Import, or an Import during a Delete, would both
        // reach the device concurrently.
        guard operationState.begin(.importing) else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        let cancellation = DeviceOperationCancellation()
        let stagingSession: ImportStagingSession
        do {
            stagingSession = try stagingManager.createSession()
        } catch {
            operationState.fail()
            status = "Import blocked: private staging could not be created. \(error.localizedDescription)"
            return
        }
        operationCancellation = cancellation
        operationProgress = MediaOperationProgress(kind: .importing, totalItems: items.count)
        status = "Importing \(items.count) item(s)..."
        Task { [weak self, destination = importDestination, stagingManager] in
            defer { try? stagingManager.cleanup(stagingSession) }
            guard let self else { return }
            var summary = await self.gateway.download(
                items.map(\.token),
                to: stagingSession,
                cancellation: cancellation,
                onProgress: { update in
                    self.applyOperationProgress(update, for: .importing)
                }
            )
            let itemByToken = Dictionary(uniqueKeysWithValues: items.map { ($0.token, $0) })
            var committed: [DeviceDownloadSuccess] = []
            for download in summary.successful {
                let targetName = itemByToken[download.token]?.model.name ?? download.filename
                do {
                    let output = try DestinationCommitter.commit(
                        stagedFilename: download.filename,
                        stagingDirectory: stagingSession.directory,
                        stagingIdentity: stagingSession.identity,
                        stagedIdentity: download.stagedIdentity,
                        filename: targetName,
                        destination: destination,
                        destinationIdentity: destinationIdentity
                    )
                    committed.append(DeviceDownloadSuccess(
                        token: download.token,
                        filename: output.lastPathComponent,
                        stagedIdentity: download.stagedIdentity
                    ))
                } catch {
                    summary.failed.append(DeviceOperationFailure(
                        token: download.token,
                        filename: targetName,
                        reason: error.localizedDescription
                    ))
                }
            }
            summary.successful = committed
            self.applyImportSummary(summary, destination: destination, requestedItems: items)
        }
    }

    func deleteSelected() {
        guard !operationState.isBusy else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        guard let snapshot = pendingDeleteSnapshot, !snapshot.items.isEmpty else {
            status = "Select one or more items to delete."
            return
        }
        let currentGeneration = allItems.first?.token.generation
        guard snapshot.catalogGeneration == currentGeneration else {
            pendingDeleteSnapshot = nil
            status = "Delete selection expired after the catalog changed. Review and confirm again."
            return
        }
        pendingDeleteSnapshot = nil
        // Destructive and previously unguarded, so a double-click on the confirmation
        // could submit the same delete twice.
        guard operationState.begin(.deleting) else {
            status = "\(operationState.current.verb) already in progress."
            return
        }
        let pendingAudit = DeleteReconciler.unverified(
            snapshot: snapshot,
            reason: "Delete confirmation saved; device verification has not completed."
        )
        guard persistRequiredDeleteRecord(makeDeleteRecord(audit: pendingAudit)) else {
            operationState.fail()
            status = "Delete blocked: the required local audit could not be saved."
            return
        }
        let cancellation = DeviceOperationCancellation()
        operationCancellation = cancellation
        operationProgress = MediaOperationProgress(kind: .deleting, totalItems: snapshot.items.count)
        status = "Deleting \(snapshot.items.count) item(s)..."
        deleteSubmissionCountForTesting += 1
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await self.gateway.delete(
                    snapshot.items.map(\.token),
                    confirmed: true,
                    cancellation: cancellation,
                    onProgress: { update in
                        self.applyOperationProgress(update, for: .deleting)
                    }
                )
                self.beginVerification(snapshot: snapshot, summary: summary)
            } catch {
                let summary = DeviceGatewayDeleteSummary(failed: snapshot.items.map {
                    DeviceOperationFailure(
                        token: $0.token,
                        filename: $0.filename,
                        reason: error.localizedDescription
                    )
                })
                self.beginVerification(snapshot: snapshot, summary: summary)
            }
        }
    }

    func cancelCurrentOperation() {
        guard var progress = operationProgress,
              progress.requestCancellation() else {
            return
        }
        let phase = progress.phase
        operationProgress = progress
        status = progress.detail
        _ = operationCancellation?.cancel()

        // Cancel must settle the UI within a bounded time even if ImageCaptureCore never
        // acknowledges. During verification the owning task is canceled directly, which is
        // what the old code was missing: it signalled only the previous submission's
        // cancellation object, so the verification scan ran on to its full timeout.
        if phase == .verifying {
            verificationTask?.cancel()
        }
        startCancellationSettleWatchdog()
    }

    /// Backstop for a cancel the framework never answers.
    ///
    /// The operation is settled as verification-pending rather than as canceled-and-clean,
    /// because a silent framework leaves the current item genuinely uncertain.
    private func startCancellationSettleWatchdog() {
        let generation = operationState.generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.cancellationSettleBound)
            guard let self,
                  self.operationState.isCurrent(generation: generation),
                  let progress = self.operationProgress,
                  progress.isCanceling else {
                return
            }
            self.verificationTask?.cancel()
            self.verificationTask = nil
            self.activeVerificationID = nil
            self.operationProgress = nil
            self.operationCancellation = nil
            self.operationState.finish()
            self.status = "Canceled without device acknowledgement. The result is unconfirmed — open Results to retry verification."
        }
    }

    func showOperationHistory() {
        isShowingOperationHistory = true
    }

    func clearOperationHistory() {
        do {
            try operationResultStore.clear()
            let loaded = operationResultStore.load()
            operationHistory = loaded.records
            operationHistoryWarning = loaded.records.contains(where: \.isPendingDeleteAudit)
                ? "Pending delete verification records are retained until verification completes."
                : loaded.warning
        } catch {
            operationHistoryWarning = "Saved operation results could not be cleared: \(error.localizedDescription)"
        }
    }

    func retryDeleteVerification(recordID: UUID) {
        guard !operationState.isBusy,
              let audit = operationHistory.first(where: { $0.id == recordID })?.deleteAudit,
              audit.verificationState == .pending,
              operationState.begin(.scanning) else {
            return
        }
        status = "Verifying the saved delete audit…"
        // Scan-only by construction: this path never calls `gateway.delete`.
        operationProgress = MediaOperationProgress(
            kind: .deleting,
            totalItems: audit.snapshot.items.count
        )
        operationCancellation = DeviceOperationCancellation()
        beginVerification(
            snapshot: audit.snapshot,
            summary: audit.frameworkSummary ?? DeviceGatewayDeleteSummary()
        )
    }

    /// Requests the destructive confirmation sheet. Does not delete anything.
    func requestDeleteConfirmation() {
        let items = selectedActionItems
        guard !items.isEmpty else {
            status = "Select one or more items to delete."
            return
        }
        pendingDeleteSnapshot = DeletePlanSnapshot(
            deviceName: deviceName,
            deviceIdentityHash: deviceIdentityHash,
            items: items.map {
                DeletePlanSnapshot.Item(
                    token: $0.token,
                    filename: $0.model.name,
                    kind: $0.model.kind,
                    size: $0.model.size
                )
            }
        )
        isConfirmingDelete = true
    }

    func cancelDeleteConfirmation() {
        pendingDeleteSnapshot = nil
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

        Task { [weak self] in
            guard let self else {
                return
            }
            var loaded: [(id: String, image: NSImage)] = []
            for item in missing {
                guard let data = try? await self.gateway.thumbnailData(
                    for: item.token,
                    maxPixelSize: 512,
                    timeout: .seconds(6)
                ), let image = InspectorPreviewProvider.decode(data, maxPixelSize: 512) else {
                    continue
                }
                loaded.append((id: item.id, image: image))
            }
            guard !loaded.isEmpty else {
                self.finishThumbnailRequests(ids: missing.map(\.id), generation: generation)
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.cacheThumbnails(loaded, completedIDs: missing.map(\.id), generation: generation)
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

    func loadInspectorPreview(for item: MediaItem) {
        let selectionChanged = inspectorPreviewSelectedID != item.id
        inspectorPreviewSelectedID = item.id
        inspectorPreviewDesiredItem = item
        if selectionChanged {
            inspectorPreviewFailedSelectionID = nil
        }

        if inspectorPreviewCache[item.id] != nil {
            touchInspectorPreview(item.id)
            inspectorPreviewDesiredItem = nil
            return
        }
        startDesiredInspectorPreviewIfPossible()
    }

    func clearInspectorPreviewSelection() {
        inspectorPreviewSelectedID = nil
        inspectorPreviewDesiredItem = nil
        inspectorPreviewFailedSelectionID = nil
    }

    func inspectorPreviewImage(for item: MediaItem) -> NSImage? {
        inspectorPreviewCache[item.id] ?? thumbnailCache[item.id]
    }

    private func startDesiredInspectorPreviewIfPossible() {
        guard inspectorPreviewActive == nil,
              let item = inspectorPreviewDesiredItem,
              inspectorPreviewCache[item.id] == nil,
              inspectorPreviewFailedSelectionID != item.id else {
            return
        }

        let generation = operationState.generation
        let token = UUID()
        inspectorPreviewActive = (token, item, generation)
        inspectorPreviewDesiredItem = nil
        let maxPixelSize = InspectorPreviewProvider.requestedMaxPixelSize(
            width: item.model.width,
            height: item.model.height
        )
        inspectorPreviewTimeoutTask?.cancel()
        let timeout = inspectorPreviewTimeout
        inspectorPreviewTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finishInspectorPreview(token: token, image: nil)
        }
        inspectorPreviewRequest(item.token, maxPixelSize) { [weak self] image in
            Task { @MainActor in
                self?.finishInspectorPreview(token: token, image: image)
            }
        }
    }

    private func finishInspectorPreview(token: UUID, image: NSImage?) {
        guard let active = inspectorPreviewActive, active.token == token else { return }
        inspectorPreviewTimeoutTask?.cancel()
        inspectorPreviewTimeoutTask = nil
        inspectorPreviewActive = nil

        guard operationState.isCurrent(generation: active.generation) else { return }
        if let image {
            insertInspectorPreview(image, for: active.item.id)
        } else if inspectorPreviewSelectedID == active.item.id {
            inspectorPreviewFailedSelectionID = active.item.id
        }
        startDesiredInspectorPreviewIfPossible()
    }

    private func insertInspectorPreview(_ image: NSImage, for id: String) {
        if let previousCost = inspectorPreviewCostByID[id] {
            inspectorPreviewTotalCost -= previousCost
        }
        inspectorPreviewAccessOrder.removeAll { $0 == id }

        let cost = Self.thumbnailCost(of: image)
        inspectorPreviewCache[id] = image
        inspectorPreviewCostByID[id] = cost
        inspectorPreviewTotalCost += cost
        inspectorPreviewAccessOrder.append(id)
        trimInspectorPreviewCacheIfNeeded()
    }

    private func touchInspectorPreview(_ id: String) {
        inspectorPreviewAccessOrder.removeAll { $0 == id }
        inspectorPreviewAccessOrder.append(id)
    }

    private func trimInspectorPreviewCacheIfNeeded() {
        while inspectorPreviewCache.count > Self.inspectorPreviewCountLimit
            || (inspectorPreviewTotalCost > Self.inspectorPreviewCostLimit
                && !inspectorPreviewAccessOrder.isEmpty) {
            let id = inspectorPreviewAccessOrder.removeFirst()
            inspectorPreviewCache.removeValue(forKey: id)
            inspectorPreviewTotalCost -= inspectorPreviewCostByID.removeValue(forKey: id) ?? 0
        }
        inspectorPreviewTotalCost = max(0, inspectorPreviewTotalCost)
    }

    private func resetInspectorPreviews() {
        inspectorPreviewTimeoutTask?.cancel()
        inspectorPreviewTimeoutTask = nil
        inspectorPreviewSelectedID = nil
        inspectorPreviewDesiredItem = nil
        inspectorPreviewFailedSelectionID = nil
        inspectorPreviewActive = nil
        inspectorPreviewCache.removeAll()
        inspectorPreviewAccessOrder.removeAll()
        inspectorPreviewCostByID.removeAll()
        inspectorPreviewTotalCost = 0
    }

    private func applyScanPayload(
        _ payload: ScanPayload,
        preservingImportedDownloads: Bool = false
    ) {
        var importedURLsByFingerprint: [DeviceFileFingerprint: URL] = [:]
        if preservingImportedDownloads {
            for item in allItems {
                if let fileURL = importedFileURLsByItemID[item.id] {
                    importedURLsByFingerprint[item.token.fingerprint] = fileURL
                }
            }
        }
        deviceName = payload.deviceName
        deviceIdentityHash = payload.deviceIdentityHash
        allItems = payload.items
        duplicatePlan = payload.plan
        selection = MediaSelectionState()
        // The previous session's outstanding requests are meaningless now.
        thumbnailRequests.cancelAll()
        metadataRequests.cancelAll()
        resetInspectorPreviews()
        // A scan can land while the user is mid-word. Applying the pending query now keeps
        // the visible field and the filtered catalog in agreement, instead of showing an
        // unfiltered list under a non-empty search box until the debounce fires.
        flushPendingSearch()
        refreshVisibleOrder()
        importedItemIDs.removeAll()
        importedFileURLsByItemID.removeAll()
        if preservingImportedDownloads {
            for item in payload.items {
                if let fileURL = importedURLsByFingerprint[item.token.fingerprint] {
                    importedItemIDs.insert(item.id)
                    importedFileURLsByItemID[item.id] = fileURL
                }
            }
            reconcileImportedDownloads()
        }
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
        Task { [weak self] in
            guard let self else {
                return
            }
            let summary = try? await self.gateway.metadata(for: item.token, timeout: .seconds(30))
            self.cacheMetadata(summary, id: item.id, generation: generation)
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

    private func applyImportSummary(_ summary: DeviceGatewayImportSummary, destination: URL, requestedItems: [MediaItem]) {
        if let filename = summary.successful.last?.filename {
            lastImportedFileURL = destination.appendingPathComponent(filename)
        }
        let requestedIDsByToken = Dictionary(uniqueKeysWithValues: requestedItems.map {
            ($0.token, $0.id)
        })
        for successfulDownload in summary.successful {
            guard let itemID = requestedIDsByToken[successfulDownload.token] else {
                continue
            }
            recordSuccessfulDownload(
                itemID: itemID,
                fileURL: destination.appendingPathComponent(successfulDownload.filename)
            )
        }
        status = "Imported \(summary.successful.count) item(s), \(summary.failed.count) failed, \(summary.canceled.count) canceled."
        persistOperationResult(OperationResultRecord(
            id: UUID(),
            date: Date(),
            kind: .importing,
            destinationPath: destination.path,
            requestedCount: requestedItems.count,
            successfulCount: summary.successful.count,
            failures: summary.failed.map { failure in
                OperationResultRecord.Failure(
                    filename: failure.filename,
                    reason: failure.reason
                )
            },
            canceledFilenames: summary.canceled.map(\.fingerprint.name)
        ))
        operationProgress = nil
        operationCancellation = nil
        operationState.finish()
    }

    /// How long a verification rescan may run before it is abandoned as pending.
    ///
    /// Deliberately far below the previous 180 seconds. Verification is a read-only catalog
    /// rescan whose only honest failure mode is "could not confirm"; making the user wait
    /// three minutes for that answer, under a label that said `Deleting`, was the defect.
    static let verificationTimeout: Duration = .seconds(45)

    /// How long the UI waits for the framework to acknowledge a cancellation before it
    /// settles anyway. The operation is then recorded as verification-pending.
    static let cancellationSettleBound: Duration = .seconds(3)

    /// The verification task, owned so Cancel can actually stop it. Previously the
    /// verification scan consumed no cancellation object and its task was never canceled,
    /// so Cancel changed the label to `Canceling delete…` while the scan ran to its timeout.
    private var verificationTask: Task<Void, Never>?

    /// Identifies the verification currently allowed to settle the UI.
    ///
    /// A canceled task can still run to its next suspension point and arrive at a terminal
    /// branch after the cancel watchdog has already settled the operation. Without this,
    /// that late arrival would persist a second audit record for work the user stopped.
    private var activeVerificationID: UUID?

    /// Whether the framework delete was provably never submitted.
    ///
    /// When nothing reached the device there is nothing to verify, so the operation
    /// finishes promptly and honestly instead of entering a long verification phase.
    private func wasNeverSubmitted(
        snapshot: DeletePlanSnapshot,
        summary: DeviceGatewayDeleteSummary
    ) -> Bool {
        guard summary.successful.isEmpty, summary.canceled.isEmpty else { return false }
        guard summary.failed.count == snapshot.items.count, !summary.failed.isEmpty else {
            return false
        }
        let neverSubmitted = DeviceGatewayError.noDevice.localizedDescription
        return summary.failed.allSatisfy { $0.reason == neverSubmitted }
    }

    /// Starts post-delete verification. Test seam for the phase and its cancellation.
    func startDeleteVerificationForTesting(
        snapshot: DeletePlanSnapshot,
        summary: DeviceGatewayDeleteSummary
    ) {
        if !operationState.isBusy {
            operationState.begin(.deleting)
        }
        if operationProgress == nil {
            operationProgress = MediaOperationProgress(kind: .deleting, totalItems: snapshot.items.count)
        }
        if operationCancellation == nil {
            operationCancellation = DeviceOperationCancellation()
        }
        beginVerification(snapshot: snapshot, summary: summary)
    }

    /// Runs verification in an owned, cancelable task.
    private func beginVerification(
        snapshot: DeletePlanSnapshot,
        summary: DeviceGatewayDeleteSummary
    ) {
        // Nothing reached the device: finish now rather than making the user sit through a
        // misleading destructive-looking phase for an answer already known.
        if wasNeverSubmitted(snapshot: snapshot, summary: summary) {
            finishVerification(
                audit: DeleteReconciler.unverified(
                    snapshot: snapshot,
                    reason: summary.failed.first?.reason
                        ?? DeviceGatewayError.noDevice.localizedDescription,
                    frameworkSummary: summary
                ),
                status: "Delete was not submitted: \(DeviceGatewayError.noDevice.localizedDescription) Nothing was removed."
            )
            return
        }

        if var progress = operationProgress {
            progress.beginVerification()
            operationProgress = progress
            status = progress.detail
        }

        verificationTask?.cancel()
        let verificationID = UUID()
        activeVerificationID = verificationID
        verificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let catalog = try await self.verificationScan(Self.verificationTimeout)
                // A cancel that landed while the scan was in flight wins: a catalog fetched
                // after the user asked to stop must not silently remove rows.
                try Task.checkCancellation()
                guard self.activeVerificationID == verificationID else { return }
                let audit = DeleteReconciler.reconcile(
                    snapshot: snapshot,
                    summary: summary,
                    catalog: catalog
                )
                self.applyScanPayload(self.makeScanPayload(catalog), preservingImportedDownloads: true)
                let removed = audit.items.filter { $0.outcome == .confirmedRemoved }.count
                let unresolved = audit.items.count - removed
                self.finishVerification(
                    audit: audit,
                    status: "Delete verified: \(removed) removed, \(unresolved) still present or unresolved."
                )
            } catch is CancellationError {
                guard self.activeVerificationID == verificationID else { return }
                self.finishCanceledVerification(snapshot: snapshot, summary: summary)
            } catch {
                guard self.activeVerificationID == verificationID else { return }
                self.finishVerification(
                    audit: DeleteReconciler.unverified(
                        snapshot: snapshot,
                        reason: error.localizedDescription,
                        frameworkSummary: summary
                    ),
                    status: "Delete finished, but verification is pending. Open Results to retry verification."
                )
            }
        }
    }

    /// Settles a canceled verification. The requested items keep their rows and are recorded
    /// as verification-pending: a canceled operation may never claim a removal.
    private func finishCanceledVerification(
        snapshot: DeletePlanSnapshot,
        summary: DeviceGatewayDeleteSummary
    ) {
        finishVerification(
            audit: DeleteReconciler.unverified(
                snapshot: snapshot,
                reason: "Verification was canceled before the device catalog could confirm the result.",
                frameworkSummary: summary
            ),
            status: "Verification canceled. The result is unconfirmed — open Results to retry verification."
        )
    }

    private func finishVerification(audit: DeleteAudit, status: String) {
        // Claims the settlement, so a late arrival from the same operation is ignored.
        activeVerificationID = nil
        verificationTask = nil
        persistOperationResult(makeDeleteRecord(audit: audit))
        self.status = status
        operationProgress = nil
        operationCancellation = nil
        operationState.finish()
    }

    private func makeScanPayload(_ snapshot: DeviceCatalogSnapshot) -> ScanPayload {
        let items = snapshot.files.map { MediaItem(model: $0.model, token: $0.token) }
        return ScanPayload(
            deviceName: snapshot.deviceName,
            deviceIdentityHash: snapshot.deviceIdentityHash,
            items: items,
            plan: DuplicatePlanner.plan(files: items.map(\.model), rule: .nameKindSize)
        )
    }

    private func makeDeleteRecord(audit: DeleteAudit) -> OperationResultRecord {
        let successfulCount = audit.items.filter { $0.outcome == .confirmedRemoved }.count
        let failures = audit.items.compactMap { item -> OperationResultRecord.Failure? in
            switch item.outcome {
            case .confirmedRemoved, .canceled:
                return nil
            case .stillPresent, .frameworkFailed, .ambiguous, .verificationPending:
                return OperationResultRecord.Failure(
                    filename: item.filename,
                    reason: item.reason ?? item.outcome.title
                )
            }
        }
        return OperationResultRecord(
            id: audit.snapshot.id,
            date: audit.snapshot.date,
            kind: .deleting,
            destinationPath: nil,
            requestedCount: audit.items.count,
            successfulCount: successfulCount,
            failures: failures,
            canceledFilenames: audit.items
                .filter { $0.outcome == .canceled }
                .map(\.filename),
            deleteAudit: audit
        )
    }

    private func persistRequiredDeleteRecord(_ record: OperationResultRecord) -> Bool {
        do {
            operationHistory = try operationResultStore.append(record)
            operationHistoryWarning = nil
            return true
        } catch {
            operationHistoryWarning = "The required delete audit could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    /// Reconciles state derived from the current catalog after the device confirms which
    /// requested items were actually deleted. Failed and canceled IDs are intentionally
    /// absent, so their catalog rows and imported badges remain visible.
    func applySuccessfulDeletion(itemIDs: Set<String>) {
        allItems.removeAll { itemIDs.contains($0.id) }
        importedItemIDs.subtract(itemIDs)
        for itemID in itemIDs {
            importedFileURLsByItemID.removeValue(forKey: itemID)
        }
        duplicatePlan = DuplicatePlanner.plan(files: allItems.map(\.model), rule: .nameKindSize)
        refreshVisibleOrder()
    }

    func recordSuccessfulDownload(itemID: String, fileURL: URL) {
        importedFileURLsByItemID[itemID] = fileURL.standardizedFileURL
        importedItemIDs.insert(itemID)
    }

    /// Reconciles the session badge with the local copy after the user returns from Finder.
    /// The device catalog item remains; only the stale local-download decoration is removed.
    func reconcileImportedDownloads() {
        let missingItemIDs = Set(importedFileURLsByItemID.compactMap { itemID, fileURL in
            isExistingRegularFile(fileURL) ? nil : itemID
        })
        guard !missingItemIDs.isEmpty else { return }

        importedItemIDs.subtract(missingItemIDs)
        for itemID in missingItemIDs {
            importedFileURLsByItemID.removeValue(forKey: itemID)
        }
        if !operationState.isBusy {
            status = "Downloaded \(importedItemIDs.count) item(s) remain locally."
        }
        if let lastImportedFileURL, !isExistingRegularFile(lastImportedFileURL) {
            self.lastImportedFileURL = nil
        }
    }

    private func isExistingRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeRegular
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

    private func persistOperationResult(_ record: OperationResultRecord) {
        guard record.shouldPersist else { return }
        do {
            operationHistory = try operationResultStore.append(record)
            operationHistoryWarning = nil
            if record.hasIssues {
                isShowingOperationHistory = true
            }
        } catch {
            operationHistoryWarning = "This result could not be saved: \(error.localizedDescription)"
            status += " The detailed result could not be saved."
        }
    }

    private func trimMetadataCacheIfNeeded() {
        while metadataAccessOrder.count > maxCachedMetadataSummaries {
            let id = metadataAccessOrder.removeFirst()
            metadataCache.removeValue(forKey: id)
        }
    }
}
