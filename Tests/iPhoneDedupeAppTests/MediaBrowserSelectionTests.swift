import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// Integration coverage for the view model's use of `MediaSelectionState`.
///
/// These tests never touch a device: `ICCameraFile()` is an empty placeholder object and
/// no scan, import, or delete path is exercised here.
@MainActor
final class MediaBrowserSelectionTests: XCTestCase {
    private func item(_ id: String, name: String? = nil, kind: String = "heic", size: Int64 = 1_000) -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: DeviceMediaFile(
                id: id,
                name: name ?? "\(id).heic",
                kind: kind,
                size: size,
                timestamp: nil,
                width: nil,
                height: nil
            ),
            cameraFile: ICCameraFile()
        )
    }

    private func viewModel(_ ids: [String] = ["a", "b", "c", "d"]) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = ids.map { item($0) }
        viewModel.sortField = .name
        viewModel.sortOrder = .ascending
        viewModel.refreshVisibleOrder()
        viewModel.setFocusOwner(.mediaBrowser)
        return viewModel
    }

    func testSelectFocusesItemAndShowsInspector() {
        let viewModel = viewModel()
        viewModel.select(item("b"))

        XCTAssertEqual(viewModel.selectedItemID, "b")
        XCTAssertTrue(viewModel.isInspectorVisible)
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testArrowMovementDoesNotGrowActionSelection() {
        let viewModel = viewModel()
        viewModel.moveFocus(by: 1, extendingSelection: false)
        viewModel.moveFocus(by: 1, extendingSelection: false)

        XCTAssertEqual(viewModel.selectedItemID, "b")
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testShiftArrowExtendsActionSelectionFromAnchor() {
        let viewModel = viewModel()
        viewModel.select(item("a"))
        viewModel.moveFocus(by: 1, extendingSelection: true)
        viewModel.moveFocus(by: 1, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedActionIDs, ["a", "b", "c"])
        XCTAssertEqual(viewModel.selectedItemID, "c")
    }

    func testSpaceTogglesFocusedItemOnly() {
        let viewModel = viewModel()
        viewModel.select(item("c"))

        XCTAssertTrue(viewModel.toggleFocusedItem())
        XCTAssertEqual(viewModel.selectedActionIDs, ["c"])
    }

    func testSelectAllVisibleUsesFilteredOrderOnly() {
        let viewModel = viewModel()
        viewModel.searchText = "a.heic"
        viewModel.selectAllVisible()

        XCTAssertEqual(viewModel.selectedActionIDs, ["a"])
    }

    func testClearSelectionKeepsInspectorVisible() {
        let viewModel = viewModel()
        viewModel.select(item("b"))
        viewModel.toggleActionSelection(item("b"))
        XCTAssertTrue(viewModel.isInspectorVisible)

        XCTAssertTrue(viewModel.clearSelection())

        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
        XCTAssertTrue(viewModel.isInspectorVisible)
    }

    func testSearchFocusBlocksMediaShortcuts() {
        let viewModel = viewModel()
        viewModel.select(item("b"))
        viewModel.setFocusOwner(.search)

        XCTAssertNil(viewModel.moveFocus(by: 1, extendingSelection: false))
        XCTAssertFalse(viewModel.toggleFocusedItem())
        XCTAssertFalse(viewModel.clearSelection())
        XCTAssertEqual(viewModel.selectedItemID, "b")
    }

    func testScopeChangeDropsSelectionThatLeftTheVisibleOrder() {
        let viewModel = viewModel()
        viewModel.select(item("b"))
        viewModel.toggleActionSelection(item("b"))

        // "b" is not a duplicate candidate, so the duplicates scope hides it.
        viewModel.selectReviewScope(.duplicates)

        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testSearchNarrowingReconcilesSelectionOnRefresh() {
        let viewModel = viewModel()
        viewModel.selectAllVisible()
        XCTAssertEqual(viewModel.selectedActionIDs.count, 4)

        viewModel.searchText = "c.heic"
        viewModel.refreshVisibleOrder()

        XCTAssertEqual(viewModel.selectedActionIDs, ["c"])
    }

    func testContextMenuSelectionReplacesSelectionOnlyForUnselectedItem() {
        let viewModel = viewModel()
        viewModel.toggleActionSelection(item("a"))
        viewModel.toggleActionSelection(item("b"))

        viewModel.prepareContextActionSelection(for: item("a"))
        XCTAssertEqual(viewModel.selectedActionIDs, ["a", "b"])

        viewModel.prepareContextActionSelection(for: item("d"))
        XCTAssertEqual(viewModel.selectedActionIDs, ["d"])
    }
}
