import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// The visible catalog is derived once per state change and cached.
///
/// Before this, `filteredItems` rebuilt arrays, sets, dictionaries, search results, and
/// sorted results on *every read*, and it was read from the status bar, both renderers,
/// `refreshVisibleOrder()`, and `selectedItem`. On a 4,000-item catalog that was several
/// O(n log n) passes per keystroke, which is what made the UI feel sluggish.
@MainActor
final class CatalogSnapshotTests: XCTestCase {
    private func items(_ count: Int) -> [MediaBrowserViewModel.MediaItem] {
        (0..<count).map { index in
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "id-\(index)",
                    name: String(format: "IMG_%04d.HEIC", index),
                    kind: index.isMultiple(of: 3) ? "mov" : "heic",
                    size: Int64((index % 500) * 1_024),
                    timestamp: "2026-06-\(String(format: "%02d", (index % 28) + 1))T10:00:00Z",
                    width: 4_032,
                    height: 3_024,
                    duration: index.isMultiple(of: 3) ? Double(index % 120) : nil
                ),
                cameraFile: ICCameraFile()
            )
        }
    }

    private func viewModel(count: Int) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = items(count)
        viewModel.refreshVisibleOrder()
        return viewModel
    }

    // MARK: - Correctness of the cached snapshot

    func testSnapshotMatchesTheCatalog() {
        let viewModel = viewModel(count: 100)
        XCTAssertEqual(viewModel.visibleItems.count, 100)
    }

    func testSnapshotUpdatesWhenSearchChanges() {
        let viewModel = viewModel(count: 100)
        viewModel.searchText = "IMG_0007"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.map(\.model.name), ["IMG_0007.HEIC"])
    }

    func testSnapshotUpdatesWhenSortChanges() {
        let viewModel = viewModel(count: 50)
        viewModel.applySort(field: .name, order: .ascending)
        let ascending = viewModel.visibleItems.map(\.id)

        viewModel.applySort(field: .name, order: .descending)
        let descending = viewModel.visibleItems.map(\.id)

        XCTAssertEqual(ascending, descending.reversed())
    }

    func testSnapshotUpdatesWhenScopeChanges() {
        let viewModel = viewModel(count: 100)
        viewModel.selectReviewScope(.duplicates)

        XCTAssertLessThanOrEqual(viewModel.visibleItems.count, 100)
    }

    func testSnapshotUpdatesWhenCatalogChanges() {
        let viewModel = viewModel(count: 10)
        viewModel.allItems = items(4)
        viewModel.refreshVisibleOrder()

        XCTAssertEqual(viewModel.visibleItems.count, 4)
    }

    func testSuccessfulDeletionClearsOnlySuccessfulImportedItems() {
        let viewModel = viewModel(count: 3)
        viewModel.importedItemIDs = ["id-0", "id-1", "id-2"]

        viewModel.applySuccessfulDeletion(itemIDs: ["id-0", "id-2"])

        XCTAssertEqual(viewModel.allItems.map(\.id), ["id-1"])
        XCTAssertEqual(viewModel.importedItemIDs, ["id-1"])
    }

    func testMissingLocalDownloadClearsBadgeWithoutRemovingDeviceItem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-imported-badge-\(UUID().uuidString)", isDirectory: true)
        let downloadedFile = directory.appendingPathComponent("IMG_0000.HEIC")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("downloaded".utf8).write(to: downloadedFile)
        let viewModel = viewModel(count: 1)
        viewModel.recordSuccessfulDownload(itemID: "id-0", fileURL: downloadedFile)
        viewModel.status = "Imported 1 item(s), 0 failed, 0 canceled."
        viewModel.reconcileImportedDownloads()
        XCTAssertEqual(viewModel.importedItemIDs, ["id-0"])

        try FileManager.default.removeItem(at: downloadedFile)
        viewModel.reconcileImportedDownloads()

        XCTAssertTrue(viewModel.importedItemIDs.isEmpty)
        XCTAssertEqual(viewModel.allItems.map(\.id), ["id-0"])
        XCTAssertEqual(viewModel.status, "Downloaded 0 item(s) remain locally.")
    }

    func testLocalDownloadReconciliationDoesNotReplaceActiveOperationStatus() {
        let viewModel = viewModel(count: 1)
        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-missing-\(UUID().uuidString).HEIC")
        viewModel.recordSuccessfulDownload(itemID: "id-0", fileURL: missingFile)
        XCTAssertTrue(viewModel.beginOperationForTesting(.importing))
        viewModel.status = "Importing 1 item(s)..."

        viewModel.reconcileImportedDownloads()

        XCTAssertEqual(viewModel.status, "Importing 1 item(s)...")
    }

    func testEmptyCatalogProducesAnEmptySnapshot() {
        let viewModel = viewModel(count: 0)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
        XCTAssertNil(viewModel.selectedItem)
    }

    func testSingleItemCatalog() {
        let viewModel = viewModel(count: 1)
        XCTAssertEqual(viewModel.visibleItems.count, 1)
    }

    // MARK: - The snapshot is actually reused

    func testRepeatedReadsDoNotRederiveTheCatalog() {
        let viewModel = viewModel(count: 500)
        let derivationsAfterFirstRead = viewModel.catalogDerivationCount

        for _ in 0..<50 {
            _ = viewModel.visibleItems
            _ = viewModel.visibleItems.count
            _ = viewModel.selectedItem
        }

        XCTAssertEqual(
            viewModel.catalogDerivationCount,
            derivationsAfterFirstRead,
            "reading the visible catalog must not recompute it"
        )
    }

    func testOneStateChangeCausesExactlyOneDerivation() {
        let viewModel = viewModel(count: 200)
        let before = viewModel.catalogDerivationCount

        viewModel.searchText = "IMG_01"

        viewModel.flushPendingSearch()
        _ = viewModel.visibleItems
        _ = viewModel.visibleItems
        _ = viewModel.visibleItems

        XCTAssertEqual(viewModel.catalogDerivationCount, before + 1)
    }

    func testSelectedItemLookupIsNotAFullScan() {
        let viewModel = viewModel(count: 1_000)
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectItem(withID: "id-999")
        let before = viewModel.catalogDerivationCount

        for _ in 0..<100 {
            _ = viewModel.selectedItem
        }

        XCTAssertEqual(viewModel.catalogDerivationCount, before)
        XCTAssertEqual(viewModel.selectedItem?.id, "id-999")
    }

    // MARK: - Large catalog budget

    /// A 4,000-item catalog is the documented acceptance size. Deriving it repeatedly is
    /// what produced visible stalls, so one derivation must stay comfortably fast.
    func testLargeCatalogDerivesQuickly() {
        let viewModel = viewModel(count: 4_000)

        let start = Date()
        viewModel.searchText = "IMG_2"
        viewModel.flushPendingSearch()
        _ = viewModel.visibleItems
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5, "one derivation of 4,000 items took \(elapsed)s")
    }

    func testLargeCatalogRepeatedReadsAreCheap() {
        let viewModel = viewModel(count: 4_000)
        _ = viewModel.visibleItems

        let start = Date()
        for _ in 0..<1_000 {
            _ = viewModel.visibleItems.count
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1, "1,000 cached reads took \(elapsed)s")
    }
}
