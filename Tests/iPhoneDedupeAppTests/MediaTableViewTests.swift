import AppKit
import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// Phase 2 coverage for the native table foundation.
///
/// These tests exercise geometry, column identity, and event translation only. No
/// ImageCaptureCore scan, import, or delete path is reachable from here.
@MainActor
final class MediaTableViewTests: XCTestCase {
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
            token: .fixture()
        )
    }

    private func viewModel(_ ids: [String] = ["a", "b", "c", "d", "e"]) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = ids.map { item($0) }
        viewModel.sortField = .name
        viewModel.sortOrder = .ascending
        viewModel.refreshVisibleOrder()
        viewModel.setFocusOwner(.mediaBrowser)
        return viewModel
    }

    // MARK: - Column model

    func testTableDefinesEveryDocumentedColumn() {
        XCTAssertEqual(
            MediaTableColumn.allCases.map(\.identifier),
            ["selection", "thumbnail", "name", "kind", "timestamp", "size", "duration"]
        )
    }

    func testOnlyDataColumnsAreSortable() {
        XCTAssertNil(MediaTableColumn.selection.sortField)
        XCTAssertNil(MediaTableColumn.thumbnail.sortField)
        XCTAssertEqual(MediaTableColumn.name.sortField, .name)
        XCTAssertEqual(MediaTableColumn.kind.sortField, .kind)
        XCTAssertEqual(MediaTableColumn.timestamp.sortField, .timestamp)
        XCTAssertEqual(MediaTableColumn.size.sortField, .size)
        XCTAssertEqual(MediaTableColumn.duration.sortField, .duration)
    }

    func testEveryColumnHasAPositiveMinimumWidth() {
        for column in MediaTableColumn.allCases {
            XCTAssertGreaterThan(column.minimumWidth, 0, "\(column.identifier) needs a minimum width")
            XCTAssertGreaterThanOrEqual(column.defaultWidth, column.minimumWidth, "\(column.identifier)")
        }
    }

    /// The incident's root cause was a document width derived from sidebar widths. The
    /// table's width comes only from its own columns, so this must stay sidebar-free.
    func testTotalColumnWidthDependsOnlyOnColumns() {
        let total = MediaTableColumn.allCases.reduce(0) { $0 + $1.defaultWidth }
        XCTAssertEqual(MediaTableColumn.totalDefaultWidth, total)
    }

    func testNameColumnCannotBeResizedBelowThumbnailSafeMinimum() {
        // Name must never shrink so far that checkbox/thumbnail geometry overlaps it.
        XCTAssertGreaterThanOrEqual(MediaTableColumn.name.minimumWidth, 140)
    }

    // MARK: - Row height

    func testRowHeightGrowsWithThumbnailScale() {
        let small = MediaTableMetrics.rowHeight(thumbnailSide: 24)
        let large = MediaTableMetrics.rowHeight(thumbnailSide: 64)
        XCTAssertGreaterThan(large, small)
    }

    func testRowHeightNeverCollapsesBelowSystemMinimum() {
        XCTAssertGreaterThanOrEqual(MediaTableMetrics.rowHeight(thumbnailSide: 0), 24)
    }

    // MARK: - Keyboard translation

    func testUpAndDownArrowsMoveFocusWithoutSelecting() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        XCTAssertTrue(controller.handleKey(.down, modifiers: []))
        XCTAssertEqual(viewModel.selectedItemID, "a")
        XCTAssertTrue(controller.handleKey(.down, modifiers: []))
        XCTAssertEqual(viewModel.selectedItemID, "b")
        XCTAssertTrue(controller.handleKey(.up, modifiers: []))
        XCTAssertEqual(viewModel.selectedItemID, "a")
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testShiftArrowExtendsActionSelection() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("b"))

        XCTAssertTrue(controller.handleKey(.down, modifiers: .shift))
        XCTAssertEqual(viewModel.selectedActionIDs, ["b", "c"])
    }

    func testSpaceTogglesFocusedRow() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("c"))

        XCTAssertTrue(controller.handleKey(.space, modifiers: []))
        XCTAssertEqual(viewModel.selectedActionIDs, ["c"])
    }

    func testEscapeClearsSelectionButNotInspector() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("c"))
        viewModel.toggleActionSelection(item("c"))

        XCTAssertTrue(controller.handleKey(.escape, modifiers: []))
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
        XCTAssertTrue(viewModel.isInspectorVisible)
    }

    func testCommandASelectsVisibleRows() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        XCTAssertTrue(controller.handleKey(.selectAll, modifiers: .command))
        XCTAssertEqual(viewModel.selectedActionIDs.count, 5)
    }

    func testLeftAndRightArrowsAreNotHandledByTheList() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        XCTAssertFalse(controller.handleKey(.left, modifiers: []))
        XCTAssertFalse(controller.handleKey(.right, modifiers: []))
    }

    func testEnterHasNoSelectionBinding() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("c"))

        XCTAssertFalse(controller.handleKey(.enter, modifiers: []))
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testKeysAreIgnoredWhenSearchOwnsFocus() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.setFocusOwner(.search)

        XCTAssertFalse(controller.handleKey(.down, modifiers: []))
        XCTAssertFalse(controller.handleKey(.space, modifiers: []))
        XCTAssertFalse(controller.handleKey(.selectAll, modifiers: .command))
    }

    func testContextMenuUsesDownloadForTheTransferAction() {
        let viewModel = viewModel(["a"])
        let coordinator = MediaTableView.Coordinator(viewModel: viewModel)
        coordinator.apply(items: viewModel.filteredItems)

        let titles = coordinator.contextMenu(forRow: 0)?.items.map(\.title)

        XCTAssertEqual(titles, ["Select", "", "Download “a.heic”", "Delete “a.heic”"])
    }

    // MARK: - Drag selection

    func testDragThroughRowsSelectsContiguousRange() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        controller.beginDrag(atRow: 1)
        controller.updateDrag(toRow: 3)
        controller.endDrag()

        XCTAssertEqual(viewModel.selectedActionIDs, ["b", "c", "d"])
    }

    func testDragShrinksWithoutLeavingStaleRows() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        controller.beginDrag(atRow: 0)
        controller.updateDrag(toRow: 4)
        controller.updateDrag(toRow: 1)
        controller.endDrag()

        XCTAssertEqual(viewModel.selectedActionIDs, ["a", "b"])
    }

    func testDragIgnoresOutOfRangeRows() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        controller.beginDrag(atRow: -1)
        controller.updateDrag(toRow: 99)
        controller.endDrag()

        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    // MARK: - Focus ownership

    /// Regression: arrow keys drove the sidebar because the model still claimed the media
    /// browser owned focus after the table stopped being first responder.
    func testReleasingFocusStopsMediaShortcuts() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("b"))

        viewModel.setFocusOwner(.none)

        XCTAssertFalse(controller.handleKey(.down, modifiers: []))
        XCTAssertFalse(controller.handleKey(.space, modifiers: []))
        XCTAssertEqual(viewModel.selectedItemID, "b", "focus should be kept, just not driven")
    }

    func testRegainingFocusResumesMediaShortcuts() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("b"))
        viewModel.setFocusOwner(.none)
        viewModel.setFocusOwner(.mediaBrowser)

        XCTAssertTrue(controller.handleKey(.down, modifiers: []))
        XCTAssertEqual(viewModel.selectedItemID, "c")
    }

    /// Regression: the focus highlight stayed on the last clicked row because keyboard
    /// movement never told the row views to redraw.
    func testFocusMovesToTheNextRowSoDecorationCanFollow() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        viewModel.select(item("a"))
        XCTAssertEqual(controller.row(for: viewModel.selectedItemID!), 0)

        controller.handleKey(.down, modifiers: [])
        XCTAssertEqual(controller.row(for: viewModel.selectedItemID!), 1)

        controller.handleKey(.down, modifiers: [])
        XCTAssertEqual(controller.row(for: viewModel.selectedItemID!), 2)
    }

    func testClickMovesFocusToTheClickedRow() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        controller.click(row: 3, modifiers: [])

        XCTAssertEqual(viewModel.selectedItemID, "d")
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty, "a plain click must not check the row")
    }

    // MARK: - Click versus drag

    /// Regression: a drag began on the first mouse-dragged event, so a click with a tiny
    /// hand tremor silently checked the row. A press must travel before it becomes a drag.
    func testDragActivationRequiresRealPointerTravel() {
        XCTAssertGreaterThan(MediaTableMetrics.dragActivationDistance, 0)
        XCTAssertLessThanOrEqual(
            MediaTableMetrics.dragActivationDistance,
            10,
            "too large a threshold would make real drags feel unresponsive"
        )
    }

    func testPlainClickNeverChangesActionSelection() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        controller.click(row: 0, modifiers: [])
        controller.click(row: 2, modifiers: [])
        controller.click(row: 4, modifiers: [])

        XCTAssertEqual(viewModel.selectedItemID, "e")
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testDoubleClickTogglesActionSelection() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)

        controller.doubleClick(row: 1)
        XCTAssertEqual(viewModel.selectedActionIDs, ["b"])
        XCTAssertEqual(viewModel.selectedItemID, "b")

        controller.doubleClick(row: 1)
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testCommandClickTogglesOneRowWithoutMovingFocus() {
        let viewModel = viewModel()
        let controller = MediaTableController(viewModel: viewModel)
        controller.click(row: 0, modifiers: [])

        controller.click(row: 3, modifiers: .command)

        XCTAssertEqual(viewModel.selectedActionIDs, ["d"])
        XCTAssertEqual(viewModel.selectedItemID, "a", "Command-click should not move focus")
    }

    // MARK: - Destructive confirmation gate

    func testDeleteRequestOnlyRaisesConfirmation() {
        let viewModel = viewModel()
        viewModel.toggleActionSelection(item("b"))

        viewModel.requestDeleteConfirmation()

        XCTAssertTrue(viewModel.isConfirmingDelete)
        // The item is still present: requesting confirmation must not delete anything.
        XCTAssertEqual(viewModel.allItems.count, 5)
    }

    func testDeleteRequestIsRejectedWithoutSelection() {
        let viewModel = viewModel()

        viewModel.requestDeleteConfirmation()

        XCTAssertFalse(viewModel.isConfirmingDelete)
    }

    // MARK: - Edge auto-scroll

    func testAutoScrollTriggersNearTopEdge() {
        let velocity = MediaTableMetrics.autoScrollVelocity(
            pointerY: 6,
            viewportHeight: 400
        )
        XCTAssertLessThan(velocity, 0)
    }

    func testAutoScrollTriggersNearBottomEdge() {
        let velocity = MediaTableMetrics.autoScrollVelocity(
            pointerY: 396,
            viewportHeight: 400
        )
        XCTAssertGreaterThan(velocity, 0)
    }

    func testAutoScrollIsIdleInTheMiddleOfTheViewport() {
        XCTAssertEqual(
            MediaTableMetrics.autoScrollVelocity(pointerY: 200, viewportHeight: 400),
            0
        )
    }

    func testAutoScrollAcceleratesCloserToTheEdge() {
        let near = abs(MediaTableMetrics.autoScrollVelocity(pointerY: 1, viewportHeight: 400))
        let far = abs(MediaTableMetrics.autoScrollVelocity(pointerY: 18, viewportHeight: 400))
        XCTAssertGreaterThan(near, far)
    }
}
