import AppKit
import DeduperCore
import DeviceMediaKit
import Foundation
import ImageCaptureCore

@MainActor
final class MediaBrowserViewModel: ObservableObject {
    struct MediaItem: Identifiable {
        let model: DeviceMediaFile
        let cameraFile: ICCameraFile
        var id: String { model.id }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: String { rawValue }
    }

    @Published var deviceName = "No Device"
    @Published var allItems: [MediaItem] = []
    @Published var selectedItemID: String?
    @Published var searchText = ""
    @Published var selectedKind = "All"
    @Published var sortField: MediaSortField = .timestamp
    @Published var sortOrder: DeduperCore.SortOrder = .descending
    @Published var viewMode: ViewMode = .list
    @Published var status = "Connect and unlock your iPhone, then scan."
    @Published var isScanning = false
    @Published var thumbnailCache: [String: NSImage] = [:]
    @Published var duplicatePlan = DuplicatePlan(keep: [], delete: [])

    private var scanner: DeviceSessionController?

    var kinds: [String] {
        let values = Set(allItems.map { $0.model.kind.uppercased() })
        return ["All"] + values.sorted()
    }

    var filteredItems: [MediaItem] {
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
        let filteredModels = query.apply(to: allItems.map(\.model))
        let itemByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return filteredModels.compactMap { itemByID[$0.id] }
    }

    var selectedItem: MediaItem? {
        guard let selectedItemID else {
            return filteredItems.first
        }
        return allItems.first { $0.id == selectedItemID }
    }

    var duplicateDeleteIDs: Set<String> {
        Set(duplicatePlan.delete.map(\.id))
    }

    var duplicateBytes: Int64 {
        duplicatePlan.delete.reduce(0) { $0 + $1.size }
    }

    func scan() {
        isScanning = true
        status = "Scanning connected iPhone..."
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let scanner = DeviceSessionController(timeoutSeconds: 180)
                let result = try scanner.scan()
                let items = result.files.map { MediaItem(model: $0.model, cameraFile: $0.cameraFile) }
                let plan = DuplicatePlanner.plan(files: items.map(\.model), rule: .nameKindSize)

                self.scanner = scanner
                self.deviceName = result.deviceName
                self.allItems = items
                self.duplicatePlan = plan
                self.selectedItemID = items.first?.id
                self.status = "Scanned \(items.count) items. Conservative duplicates: \(plan.delete.count)."
                self.isScanning = false
                self.loadThumbnails(for: Array(items.prefix(96)))
            } catch {
                self.status = "Scan failed: \(error)"
                self.isScanning = false
            }
        }
    }

    func select(_ item: MediaItem) {
        selectedItemID = item.id
        loadThumbnails(for: [item])
    }

    func loadThumbnails(for items: [MediaItem]) {
        let missing = items.filter { thumbnailCache[$0.id] == nil }
        guard !missing.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            for item in missing {
                guard let image = ThumbnailProvider.thumbnail(for: item.cameraFile, timeoutSeconds: 6) else {
                    continue
                }
                self.thumbnailCache[item.id] = image
            }
        }
    }
}
