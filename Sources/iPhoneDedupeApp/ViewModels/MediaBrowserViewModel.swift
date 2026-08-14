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

    private var thumbnailIDsInFlight = Set<String>()
    private var thumbnailAccessOrder: [String] = []
    private let maxCachedThumbnails = 512
    private var metadataIDsInFlight = Set<String>()

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
    }
}
