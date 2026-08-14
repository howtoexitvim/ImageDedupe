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
    @Published var selectedItemID: String?
    @Published var selectedActionIDs: Set<String> = []
    @Published var reviewScope: MediaReviewScope = .allMedia
    @Published var searchText = ""
    @Published var selectedKind = "All"
    @Published var sortField: MediaSortField = .timestamp
    @Published var sortOrder: DeduperCore.SortOrder = .descending
    @Published var viewMode: ViewMode = .list
    @Published var displayScale = MediaDisplayScale(rawValue: 1.0)
    @Published var status = "Connect and unlock your iPhone, then scan."
    @Published var isScanning = false
    @Published var thumbnailCache: [String: NSImage] = [:]
    @Published var metadataCache: [String: MediaMetadataSummary] = [:]
    @Published var duplicatePlan = DuplicatePlan(keep: [], delete: [])
    @Published var importDestination = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    @Published var lastImportedFileURL: URL?

    private var thumbnailIDsInFlight = Set<String>()
    private var thumbnailAccessOrder: [String] = []
    private let maxCachedThumbnails = 512
    private var metadataIDsInFlight = Set<String>()
    private var metadataAccessOrder: [String] = []
    private let maxCachedMetadataSummaries = 768

    var kinds: [String] {
        let values = Set(allItems.map { $0.model.kind.uppercased() })
        return ["All"] + values.sorted()
    }

    var filteredItems: [MediaItem] {
        let scopedModels = reviewScope.apply(to: allItems.map(\.model), duplicatePlan: duplicatePlan)
        let scopedIDs = Set(scopedModels.map(\.id))
        let scopedItems = allItems.filter { scopedIDs.contains($0.id) }
        var filters: [MediaFilter] = []
        if !searchText.isEmpty {
            filters.append(.nameContains(searchText))
        }
        if selectedKind != "All" {
            filters.append(.kindIn([selectedKind]))
        }
        let query = MediaQuery(
            filters: filters,
            sort: MediaSortDescriptor(field: sortField, order: sortOrder)
        )
        let filteredModels = query.apply(to: scopedItems.map(\.model))
        let itemByID = Dictionary(uniqueKeysWithValues: scopedItems.map { ($0.id, $0) })
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
        selectedItemID = item.id
        loadThumbnails(for: [item])
        loadMetadata(for: item)
    }

    func toggleActionSelection(_ item: MediaItem) {
        if selectedActionIDs.contains(item.id) {
            selectedActionIDs.remove(item.id)
        } else {
            selectedActionIDs.insert(item.id)
        }
    }

    func prepareContextActionSelection(for item: MediaItem) {
        if !selectedActionIDs.contains(item.id) {
            selectedActionIDs = [item.id]
        }
    }

    func selectAllVisible() {
        selectedActionIDs = Set(filteredItems.map(\.id))
    }

    func clearActionSelection() {
        selectedActionIDs.removeAll()
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
            await self.applyImportSummary(summary, destination: destination)
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

    func revealLastImportInFinder() {
        guard let lastImportedFileURL else {
            status = "No imported file to reveal yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([lastImportedFileURL])
    }

    func selectReviewScope(_ scope: MediaReviewScope) {
        reviewScope = scope
        if let selectedItemID,
           !filteredItems.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
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
        selectedItemID = nil
        selectedActionIDs.removeAll()
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

    private func applyImportSummary(_ summary: DeviceImportSummary, destination: URL) {
        if let filename = summary.successful.last?.filename {
            lastImportedFileURL = destination.appendingPathComponent(filename)
        }
        status = "Imported \(summary.successful.count) item(s), \(summary.failed.count) failed."
    }

    private func applyDeleteSummary(_ summary: DeviceDeleteSummary, requestedIDs: Set<String>) {
        let successfulHandles = Set(summary.successful.map(\.ptpObjectHandle))
        allItems.removeAll { item in
            requestedIDs.contains(item.id) && successfulHandles.contains(item.cameraFile.ptpObjectHandle)
        }
        selectedActionIDs.subtract(requestedIDs)
        if let selectedItemID, requestedIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
        duplicatePlan = DuplicatePlanner.plan(files: allItems.map(\.model), rule: .nameKindSize)
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
