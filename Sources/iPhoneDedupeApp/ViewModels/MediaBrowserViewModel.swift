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
    @Published var allItems: [MediaItem] = []

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

    @Published var reviewScope: MediaReviewScope = .allMedia
    @Published var searchText = ""
    @Published var sortField: MediaSortField = .timestamp
    @Published var sortOrder: DeduperCore.SortOrder = .descending
    @Published var viewMode: ViewMode = .list
    @Published var isInspectorVisible = false
    @Published var displayScale = MediaDisplayScale(rawValue: 1.0)
    @Published var status = "Connect and unlock your iPhone, then scan."
    @Published var isScanning = false
    @Published var thumbnailCache: [String: NSImage] = [:]
    @Published var metadataCache: [String: MediaMetadataSummary] = [:]
    @Published var importedItemIDs: Set<String> = []
    @Published var duplicatePlan = DuplicatePlan(keep: [], delete: [])
    @Published var importDestination = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    @Published var lastImportedFileURL: URL?

    private var thumbnailIDsInFlight = Set<String>()
    private var thumbnailAccessOrder: [String] = []
    private let maxCachedThumbnails = 512
    private var metadataIDsInFlight = Set<String>()
    private var metadataAccessOrder: [String] = []
    private let maxCachedMetadataSummaries = 768

    /// Publishes the current filtered order into the selection model so focus, anchor,
    /// and action selection are reconciled exactly once per state change instead of
    /// drifting behind search, sort, scope, scan, import, or delete.
    func refreshVisibleOrder() {
        selection.setVisibleIDs(filteredItems.map(\.id))
    }

    var filteredItems: [MediaItem] {
        let scopedModels = reviewScope.apply(to: allItems.map(\.model), duplicatePlan: duplicatePlan)
        let scopedIDs = Set(scopedModels.map(\.id))
        let scopedItems = allItems.filter { scopedIDs.contains($0.id) }
        let smartSearch = MediaSearchQuery(searchText)
        let searchedItems = scopedItems.filter { smartSearch.matches($0.model) }
        let query = MediaQuery(
            filters: [],
            sort: MediaSortDescriptor(field: sortField, order: sortOrder)
        )
        let filteredModels = query.apply(to: searchedItems.map(\.model))
        let itemByID = Dictionary(uniqueKeysWithValues: searchedItems.map { ($0.id, $0) })
        return filteredModels.compactMap { itemByID[$0.id] }
    }

    var selectedItem: MediaItem? {
        guard let selectedItemID else { return nil }
        return filteredItems.first { $0.id == selectedItemID }
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
        guard !isScanning else {
            return
        }
        isScanning = true
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
                self.applyScanPayload(payload)
            } catch {
                self.status = "Scan failed: \(error)"
                fputs("ui-scan-failed: \(error)\n", stderr)
                self.isScanning = false
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

    func prepareContextActionSelection(for item: MediaItem) {
        refreshVisibleOrder()
        if !selection.actionSelectedIDs.contains(item.id) {
            selection.actionSelectedIDs = [item.id]
            selection.anchorID = item.id
        }
    }

    func selectAllVisible() {
        refreshVisibleOrder()
        selection.focusOwner = .mediaBrowser
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
    }

    func importSelected() {
        let items = selectedActionItems
        guard !items.isEmpty else {
            status = "Select one or more items to import."
            return
        }
        status = "Importing \(items.count) item(s)..."
        Task.detached(priority: .userInitiated) { [weak self, destination = importDestination] in
            guard let self else { return }
            let summary = DeviceImportController(timeoutSeconds: 120).importFiles(items.map(\.cameraFile), to: destination)
            await self.applyImportSummary(summary, destination: destination, requestedItems: items)
        }
    }

    func deleteSelected() {
        let items = selectedActionItems
        guard !items.isEmpty else {
            status = "Select one or more items to delete."
            return
        }
        status = "Deleting \(items.count) item(s)..."
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard let device = items.first?.cameraFile.device else {
                await self.applyDeleteFailure("No device available for selected files.")
                return
            }
            do {
                let summary = try DeviceSessionController(timeoutSeconds: 120).delete(items.map(\.cameraFile), from: device, confirmed: true)
                await self.applyDeleteSummary(summary, requestedIDs: Set(items.map(\.id)))
            } catch {
                await self.applyDeleteFailure("\(error)")
            }
        }
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
        let missing = items.filter { item in
            thumbnailCache[item.id] == nil && !thumbnailIDsInFlight.contains(item.id)
        }
        guard !missing.isEmpty else {
            return
        }
        thumbnailIDsInFlight.formUnion(missing.map(\.id))

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
                await self.finishThumbnailRequests(ids: missing.map(\.id))
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self.cacheThumbnails(loaded, completedIDs: missing.map(\.id))
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
        refreshVisibleOrder()
        importedItemIDs.removeAll()
        status = "Scanned \(payload.items.count) items. Conservative duplicates: \(payload.plan.delete.count)."
        fputs("ui-scan-succeeded: scanned=\(payload.items.count) duplicates=\(payload.plan.delete.count)\n", stderr)
        isScanning = false
        Task { @MainActor [weak self, items = payload.items] in
            await Task.yield()
            self?.loadThumbnails(for: Array(items.prefix(96)))
        }
    }

    private func cacheThumbnails(_ images: [(id: String, image: NSImage)], completedIDs: [String]) {
        for image in images {
            thumbnailCache[image.id] = image.image
            thumbnailAccessOrder.removeAll { $0 == image.id }
            thumbnailAccessOrder.append(image.id)
        }
        finishThumbnailRequests(ids: completedIDs)
        trimThumbnailCacheIfNeeded()
    }

    private func finishThumbnailRequests(ids: [String]) {
        for id in ids {
            thumbnailIDsInFlight.remove(id)
        }
    }

    private func trimThumbnailCacheIfNeeded() {
        while thumbnailAccessOrder.count > maxCachedThumbnails {
            let id = thumbnailAccessOrder.removeFirst()
            thumbnailCache.removeValue(forKey: id)
        }
    }

    private func loadMetadata(for item: MediaItem) {
        guard metadataCache[item.id] == nil,
              !metadataIDsInFlight.contains(item.id) else {
            return
        }
        metadataIDsInFlight.insert(item.id)
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            let summary = MetadataProvider.summary(for: item.cameraFile, timeoutSeconds: 30)
            await self.cacheMetadata(summary, id: item.id)
        }
    }

    private func cacheMetadata(_ summary: MediaMetadataSummary?, id: String) {
        metadataIDsInFlight.remove(id)
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
        status = "Imported \(summary.successful.count) item(s), \(summary.failed.count) failed."
    }

    private func applyDeleteSummary(_ summary: DeviceDeleteSummary, requestedIDs: Set<String>) {
        let successfulHandles = Set(summary.successful.map(\.ptpObjectHandle))
        allItems.removeAll { item in
            requestedIDs.contains(item.id) && successfulHandles.contains(item.cameraFile.ptpObjectHandle)
        }
        duplicatePlan = DuplicatePlanner.plan(files: allItems.map(\.model), rule: .nameKindSize)
        refreshVisibleOrder()
        status = "Deleted \(summary.successful.count) item(s), \(summary.failed.count) failed, \(summary.canceled.count) canceled."
    }

    private func applyDeleteFailure(_ message: String) {
        status = "Delete failed: \(message)"
    }

    private func trimMetadataCacheIfNeeded() {
        while metadataAccessOrder.count > maxCachedMetadataSummaries {
            let id = metadataAccessOrder.removeFirst()
            metadataCache.removeValue(forKey: id)
        }
    }
}
