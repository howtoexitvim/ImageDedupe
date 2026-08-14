import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// The authoritative keyboard contract across the four focus regions: media browser
/// (List and Grid), search field, inspector, and none.
///
/// These exist because focus ownership was the root cause of two reported bugs: arrow keys
/// driving the sidebar, and Escape doing nothing in the Grid.
@MainActor
final class KeyboardOwnershipTests: XCTestCase {
    private func item(_ id: String) -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: DeviceMediaFile(
                id: id,
                name: "\(id).heic",
                kind: "heic",
                size: 1_000,
                timestamp: nil,
                width: nil,
                height: nil
            ),
            cameraFile: ICCameraFile()
        )
    }

    private func viewModel() -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = ["a", "b", "c", "d", "e", "f"].map { item($0) }
        viewModel.sortField = .name
        viewModel.sortOrder = .ascending
        viewModel.refreshVisibleOrder()
        return viewModel
    }

    // MARK: - Search owns focus

    func testSearchFocusBlocksEveryMediaShortcut() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.select(item("b"))
        viewModel.toggleActionSelection(item("b"))

        viewModel.setFocusOwner(.search)

        XCTAssertNil(viewModel.moveFocus(by: 1, extendingSelection: false))
        XCTAssertNil(viewModel.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false))
        XCTAssertFalse(viewModel.toggleFocusedItem())
        XCTAssertFalse(viewModel.clearSelection())

        // Existing selection is preserved, just not driven.
        XCTAssertEqual(viewModel.selectedItemID, "b")
        XCTAssertEqual(viewModel.selectedActionIDs, ["b"])
    }

    func testSelectAllIsBlockedWhileSearchOwnsFocus() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.search)

        viewModel.selectAllVisible()

        XCTAssertTrue(
            viewModel.selectedActionIDs.isEmpty,
            "Command-A must belong to the search field's text while it is editing"
        )
    }

    func testLeavingSearchRestoresMediaShortcuts() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.search)
        viewModel.setFocusOwner(.mediaBrowser)

        XCTAssertNotNil(viewModel.moveFocus(by: 1, extendingSelection: false))
    }

    // MARK: - Inspector owns focus

    func testInspectorFocusDoesNotClearMediaSelection() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.select(item("c"))
        viewModel.toggleActionSelection(item("c"))

        viewModel.setFocusOwner(.inspector)

        XCTAssertEqual(viewModel.selectedItemID, "c")
        XCTAssertEqual(viewModel.selectedActionIDs, ["c"])
    }

    func testInspectorFocusBlocksMediaShortcuts() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.inspector)

        XCTAssertNil(viewModel.moveFocus(by: 1, extendingSelection: false))
        XCTAssertFalse(viewModel.toggleFocusedItem())
    }

    // MARK: - Nobody owns focus (sidebar case)

    /// Regression: the sidebar received the arrow keys while the model still believed the
    /// media browser owned focus, so both moved at once.
    func testNoOwnerMeansNoMediaShortcuts() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.select(item("b"))

        viewModel.setFocusOwner(.none)

        XCTAssertNil(viewModel.moveFocus(by: 1, extendingSelection: false))
        XCTAssertFalse(viewModel.toggleFocusedItem())
        XCTAssertFalse(viewModel.clearSelection())
    }

    // MARK: - Search results reconcile selection

    func testSearchNarrowingDropsSelectionThatLeftTheResults() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectAllVisible()
        XCTAssertEqual(viewModel.selectedActionIDs.count, 6)

        viewModel.searchText = "c.heic"
        viewModel.refreshVisibleOrder()

        XCTAssertEqual(viewModel.selectedActionIDs, ["c"])
    }

    func testSearchClearingDoesNotResurrectOldSelection() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectAllVisible()

        viewModel.searchText = "c.heic"
        viewModel.refreshVisibleOrder()
        viewModel.searchText = ""
        viewModel.refreshVisibleOrder()

        XCTAssertEqual(
            viewModel.selectedActionIDs,
            ["c"],
            "items dropped by a narrower search must not come back when it widens"
        )
    }

    func testFocusSurvivesASearchThatStillIncludesIt() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.select(item("c"))

        viewModel.searchText = "c.heic"
        viewModel.refreshVisibleOrder()

        XCTAssertEqual(viewModel.selectedItemID, "c")
    }

    // MARK: - Escape never touches the inspector

    func testEscapeLeavesInspectorVisibilityAlone() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.select(item("a"))
        XCTAssertTrue(viewModel.isInspectorVisible)

        viewModel.clearSelection()

        XCTAssertTrue(viewModel.isInspectorVisible)
    }

    func testEscapeWorksIdenticallyInListAndGrid() {
        for mode in [MediaBrowserViewModel.ViewMode.list, .grid] {
            let viewModel = viewModel()
            viewModel.setViewMode(mode)
            viewModel.setFocusOwner(.mediaBrowser)
            viewModel.select(item("b"))
            viewModel.toggleActionSelection(item("b"))

            XCTAssertTrue(viewModel.clearSelection(), "Escape should clear in \(mode)")
            XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
            XCTAssertNil(viewModel.selectedItemID)
        }
    }

    func testCommandAWorksIdenticallyInListAndGrid() {
        for mode in [MediaBrowserViewModel.ViewMode.list, .grid] {
            let viewModel = viewModel()
            viewModel.setViewMode(mode)
            viewModel.setFocusOwner(.mediaBrowser)

            viewModel.selectAllVisible()

            XCTAssertEqual(viewModel.selectedActionIDs.count, 6, "Command-A should select all in \(mode)")
        }
    }
}
