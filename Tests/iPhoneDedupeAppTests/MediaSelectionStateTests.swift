import XCTest
@testable import iPhoneDedupeApp

final class MediaSelectionStateTests: XCTestCase {
    private func state(_ ids: [String] = ["a", "b", "c", "d", "e"]) -> MediaSelectionState {
        var state = MediaSelectionState()
        state.setVisibleIDs(ids)
        return state
    }

    // MARK: - Visible order and reconciliation

    func testSetVisibleIDsDropsUnknownSelection() {
        var state = state()
        state.focusedID = "c"
        state.anchorID = "c"
        state.actionSelectedIDs = ["a", "c", "e"]

        state.setVisibleIDs(["a", "b"])

        XCTAssertNil(state.focusedID)
        XCTAssertNil(state.anchorID)
        XCTAssertEqual(state.actionSelectedIDs, ["a"])
    }

    func testSetVisibleIDsKeepsValidFocusAndAnchor() {
        var state = state()
        state.focusedID = "b"
        state.anchorID = "b"
        state.actionSelectedIDs = ["b", "d"]

        state.setVisibleIDs(["a", "b", "d"])

        XCTAssertEqual(state.focusedID, "b")
        XCTAssertEqual(state.anchorID, "b")
        XCTAssertEqual(state.actionSelectedIDs, ["b", "d"])
    }

    func testSetVisibleIDsIgnoresDuplicateIDs() {
        var state = MediaSelectionState()
        state.setVisibleIDs(["a", "b", "a", "c", "b"])
        XCTAssertEqual(state.visibleIDs, ["a", "b", "c"])
    }

    func testReconcileAfterRemovalClearsRemovedSelection() {
        var state = state()
        state.focusedID = "d"
        state.anchorID = "a"
        state.actionSelectedIDs = ["c", "d"]

        state.setVisibleIDs(["a", "b", "c"])

        XCTAssertNil(state.focusedID)
        XCTAssertEqual(state.anchorID, "a")
        XCTAssertEqual(state.actionSelectedIDs, ["c"])
    }

    // MARK: - Focus movement

    func testMoveFocusFromNothingFocusesFirstVisibleItemWhenMovingForward() {
        var state = state()
        state.focusOwner = .mediaBrowser

        XCTAssertEqual(state.moveFocus(by: 1, extendingSelection: false), "a")
        XCTAssertEqual(state.focusedID, "a")
    }

    func testMoveFocusFromNothingFocusesLastVisibleItemWhenMovingBackward() {
        var state = state()
        state.focusOwner = .mediaBrowser

        XCTAssertEqual(state.moveFocus(by: -1, extendingSelection: false), "e")
        XCTAssertEqual(state.focusedID, "e")
    }

    func testMoveFocusClampsAtTopEdge() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "a"
        state.anchorID = "a"

        XCTAssertEqual(state.moveFocus(by: -1, extendingSelection: false), "a")
        XCTAssertEqual(state.focusedID, "a")
    }

    func testMoveFocusClampsAtBottomEdge() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "e"
        state.anchorID = "e"

        XCTAssertEqual(state.moveFocus(by: 3, extendingSelection: false), "e")
        XCTAssertEqual(state.focusedID, "e")
    }

    func testMoveFocusAloneDoesNotChangeActionSelection() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "a"
        state.actionSelectedIDs = ["c"]

        _ = state.moveFocus(by: 1, extendingSelection: false)
        _ = state.moveFocus(by: 1, extendingSelection: false)

        XCTAssertEqual(state.focusedID, "c")
        XCTAssertEqual(state.actionSelectedIDs, ["c"])
    }

    func testMoveFocusResetsAnchorWhenNotExtending() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "a"
        state.anchorID = "a"

        _ = state.moveFocus(by: 2, extendingSelection: false)

        XCTAssertEqual(state.anchorID, "c")
    }

    func testMoveFocusDoesNothingWhenMediaBrowserDoesNotOwnFocus() {
        var state = state()
        state.focusOwner = .search
        state.focusedID = "a"

        XCTAssertNil(state.moveFocus(by: 1, extendingSelection: false))
        XCTAssertEqual(state.focusedID, "a")
    }

    func testMoveFocusOnEmptyCatalogReturnsNil() {
        var state = MediaSelectionState()
        state.focusOwner = .mediaBrowser
        state.setVisibleIDs([])

        XCTAssertNil(state.moveFocus(by: 1, extendingSelection: false))
        XCTAssertNil(state.focusedID)
    }

    // MARK: - Grid movement

    func testMoveFocusByGridRowUsesColumnCount() {
        var state = state(["a", "b", "c", "d", "e", "f", "g"])
        state.focusOwner = .mediaBrowser
        state.focusedID = "a"

        XCTAssertEqual(state.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false), "d")
        XCTAssertEqual(state.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false), "g")
    }

    func testMoveFocusByGridRowClampsToLastItem() {
        var state = state(["a", "b", "c", "d", "e"])
        state.focusOwner = .mediaBrowser
        state.focusedID = "c"

        XCTAssertEqual(state.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false), "e")
    }

    func testMoveFocusByGridColumnMovesOneItem() {
        var state = state(["a", "b", "c", "d"])
        state.focusOwner = .mediaBrowser
        state.focusedID = "b"

        XCTAssertEqual(state.moveFocus(rows: 0, columns: 1, columnCount: 3, extendingSelection: false), "c")
        XCTAssertEqual(state.moveFocus(rows: 0, columns: -1, columnCount: 3, extendingSelection: false), "b")
    }

    func testGridMovementTreatsNonPositiveColumnCountAsSingleColumn() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "a"

        XCTAssertEqual(state.moveFocus(rows: 1, columns: 0, columnCount: 0, extendingSelection: false), "b")
    }

    // MARK: - Shift extension

    func testShiftArrowExtendsContiguousRangeFromAnchor() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "b"
        state.anchorID = "b"

        _ = state.moveFocus(by: 1, extendingSelection: true)
        _ = state.moveFocus(by: 1, extendingSelection: true)

        XCTAssertEqual(state.focusedID, "d")
        XCTAssertEqual(state.anchorID, "b")
        XCTAssertEqual(state.actionSelectedIDs, ["b", "c", "d"])
    }

    func testShiftArrowShrinksRangeWhenReversingDirection() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "b"
        state.anchorID = "b"

        _ = state.moveFocus(by: 2, extendingSelection: true)
        XCTAssertEqual(state.actionSelectedIDs, ["b", "c", "d"])

        _ = state.moveFocus(by: -1, extendingSelection: true)
        XCTAssertEqual(state.focusedID, "c")
        XCTAssertEqual(state.actionSelectedIDs, ["b", "c"])
    }

    func testShiftArrowCrossingAnchorSelectsOppositeRange() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "c"
        state.anchorID = "c"

        _ = state.moveFocus(by: -2, extendingSelection: true)

        XCTAssertEqual(state.focusedID, "a")
        XCTAssertEqual(state.actionSelectedIDs, ["a", "b", "c"])
    }

    func testShiftArrowWithoutAnchorEstablishesAnchorAtFocus() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "c"
        state.anchorID = nil

        _ = state.moveFocus(by: 1, extendingSelection: true)

        XCTAssertEqual(state.anchorID, "c")
        XCTAssertEqual(state.actionSelectedIDs, ["c", "d"])
    }

    func testShiftArrowPreservesUnrelatedSelectionOutsideRange() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.actionSelectedIDs = ["e"]
        state.focusedID = "a"
        state.anchorID = "a"

        _ = state.moveFocus(by: 1, extendingSelection: true)

        XCTAssertEqual(state.actionSelectedIDs, ["a", "b", "e"])
    }

    // MARK: - Space, Command-A, Escape

    func testSpaceTogglesExactlyTheFocusedItem() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "c"

        XCTAssertTrue(state.toggleFocusedItem())
        XCTAssertEqual(state.actionSelectedIDs, ["c"])

        XCTAssertTrue(state.toggleFocusedItem())
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testSpaceDoesNothingWithoutFocusedItem() {
        var state = state()
        state.focusOwner = .mediaBrowser

        XCTAssertFalse(state.toggleFocusedItem())
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testSpaceDoesNothingWhenSearchOwnsFocus() {
        var state = state()
        state.focusOwner = .search
        state.focusedID = "c"

        XCTAssertFalse(state.toggleFocusedItem())
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testSpaceSetsAnchorToFocusedItem() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "c"

        _ = state.toggleFocusedItem()

        XCTAssertEqual(state.anchorID, "c")
    }

    func testSelectAllVisibleSelectsOnlyCurrentFilteredOrder() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.setVisibleIDs(["b", "d"])

        XCTAssertTrue(state.selectAllVisible())
        XCTAssertEqual(state.actionSelectedIDs, ["b", "d"])
    }

    func testSelectAllVisibleIsBlockedWhenSearchOwnsFocus() {
        var state = state()
        state.focusOwner = .search

        XCTAssertFalse(state.selectAllVisible())
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testSelectAllVisibleIsBlockedWhenInspectorOwnsFocus() {
        var state = state()
        state.focusOwner = .inspector

        XCTAssertFalse(state.selectAllVisible())
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testEscapeClearsFocusAnchorAndActionSelection() {
        var state = state()
        state.focusOwner = .mediaBrowser
        state.focusedID = "c"
        state.anchorID = "a"
        state.actionSelectedIDs = ["a", "b", "c"]

        XCTAssertTrue(state.clearSelection())

        XCTAssertNil(state.focusedID)
        XCTAssertNil(state.anchorID)
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testEscapeReportsNoChangeWhenAlreadyEmpty() {
        var state = state()
        state.focusOwner = .mediaBrowser

        XCTAssertFalse(state.clearSelection())
    }

    // MARK: - Click and checkbox

    func testFocusItemSetsFocusAndAnchorWithoutChangingActionSelection() {
        var state = state()
        state.actionSelectedIDs = ["a"]

        state.focus("d")

        XCTAssertEqual(state.focusedID, "d")
        XCTAssertEqual(state.anchorID, "d")
        XCTAssertEqual(state.actionSelectedIDs, ["a"])
        XCTAssertEqual(state.focusOwner, .mediaBrowser)
    }

    func testFocusIgnoresIDsOutsideVisibleOrder() {
        var state = state()
        state.focus("zzz")

        XCTAssertNil(state.focusedID)
    }

    func testToggleActionSelectionTogglesOnlyThatItem() {
        var state = state()
        state.toggleActionSelection("b")
        XCTAssertEqual(state.actionSelectedIDs, ["b"])
        XCTAssertEqual(state.anchorID, "b")

        state.toggleActionSelection("b")
        XCTAssertEqual(state.actionSelectedIDs, [])
    }

    func testToggleActionSelectionDoesNotMoveFocus() {
        var state = state()
        state.focus("a")
        state.toggleActionSelection("d")

        XCTAssertEqual(state.focusedID, "a")
    }

    func testExtendSelectionToTargetSelectsContiguousRange() {
        var state = state()
        state.focus("b")
        state.extendSelection(to: "d")

        XCTAssertEqual(state.actionSelectedIDs, ["b", "c", "d"])
        XCTAssertEqual(state.focusedID, "d")
        XCTAssertEqual(state.anchorID, "b")
    }

    func testDragSelectionReplacesPreviousDragRange() {
        var state = state()
        state.beginDragSelection(at: "b")
        state.updateDragSelection(to: "d")
        XCTAssertEqual(state.actionSelectedIDs, ["b", "c", "d"])

        state.updateDragSelection(to: "c")
        XCTAssertEqual(state.actionSelectedIDs, ["b", "c"])

        state.endDragSelection()
        XCTAssertEqual(state.actionSelectedIDs, ["b", "c"])
    }

    func testDragSelectionPreservesSelectionMadeBeforeTheDrag() {
        var state = state()
        state.toggleActionSelection("e")
        state.beginDragSelection(at: "a")
        state.updateDragSelection(to: "b")

        XCTAssertEqual(state.actionSelectedIDs, ["a", "b", "e"])
    }

    // MARK: - Marquee selection

    func testMarqueeSelectsIntersectingItems() {
        var state = state()
        state.beginMarqueeSelection(additive: false)
        state.updateMarqueeSelection(intersecting: ["b", "c"])

        XCTAssertEqual(state.actionSelectedIDs, ["b", "c"])
    }

    /// Shrinking the marquee deselects what the marquee itself added, the same way the
    /// List's drag range shrinks.
    func testShrinkingTheMarqueeDeselectsItemsItNoLongerCovers() {
        var state = state()
        state.beginMarqueeSelection(additive: false)
        state.updateMarqueeSelection(intersecting: ["b", "c", "d"])
        state.updateMarqueeSelection(intersecting: ["b"])

        XCTAssertEqual(state.actionSelectedIDs, ["b"])
    }

    func testPlainMarqueeReplacesTheExistingSelection() {
        var state = state()
        state.toggleActionSelection("e")
        state.beginMarqueeSelection(additive: false)
        state.updateMarqueeSelection(intersecting: ["a"])

        XCTAssertEqual(state.actionSelectedIDs, ["a"])
    }

    func testAdditiveMarqueeKeepsTheExistingSelection() {
        var state = state()
        state.toggleActionSelection("e")
        state.beginMarqueeSelection(additive: true)
        state.updateMarqueeSelection(intersecting: ["a"])

        XCTAssertEqual(state.actionSelectedIDs, ["a", "e"])
    }

    func testAdditiveMarqueeShrinkingKeepsThePreDragSelection() {
        var state = state()
        state.toggleActionSelection("e")
        state.beginMarqueeSelection(additive: true)
        state.updateMarqueeSelection(intersecting: ["a", "b"])
        state.updateMarqueeSelection(intersecting: ["a"])

        XCTAssertEqual(state.actionSelectedIDs, ["a", "e"])
    }

    func testMarqueeIgnoresIDsOutsideTheVisibleOrder() {
        var state = state()
        state.beginMarqueeSelection(additive: false)
        state.updateMarqueeSelection(intersecting: ["b", "not-a-real-id"])

        XCTAssertEqual(state.actionSelectedIDs, ["b"])
    }

    func testMarqueeUpdatesAreIgnoredBeforeItBegins() {
        var state = state()
        state.updateMarqueeSelection(intersecting: ["a", "b"])

        XCTAssertTrue(state.actionSelectedIDs.isEmpty)
    }

    func testEndingTheMarqueeKeepsItsResult() {
        var state = state()
        state.beginMarqueeSelection(additive: false)
        state.updateMarqueeSelection(intersecting: ["b", "c"])
        state.endDragSelection()

        XCTAssertEqual(state.actionSelectedIDs, ["b", "c"])
        XCTAssertFalse(state.isDragSelecting)
    }

    func testMarqueeReportsDragInProgress() {
        var state = state()
        XCTAssertFalse(state.isDragSelecting)
        state.beginMarqueeSelection(additive: false)
        XCTAssertTrue(state.isDragSelecting)
    }

    func testMarqueeTakesFocusOwnership() {
        var state = state()
        state.focusOwner = .none
        state.beginMarqueeSelection(additive: false)

        XCTAssertEqual(state.focusOwner, .mediaBrowser)
    }

    // MARK: - Focus owner isolation

    func testInspectorFocusDoesNotClearMediaSelection() {
        var state = state()
        state.focus("c")
        state.actionSelectedIDs = ["a", "c"]

        state.focusOwner = .inspector

        XCTAssertEqual(state.focusedID, "c")
        XCTAssertEqual(state.actionSelectedIDs, ["a", "c"])
    }

    func testSearchFocusBlocksMediaShortcutsButKeepsSelection() {
        var state = state()
        state.focus("c")
        state.actionSelectedIDs = ["c"]

        state.focusOwner = .search

        XCTAssertNil(state.moveFocus(by: 1, extendingSelection: false))
        XCTAssertFalse(state.toggleFocusedItem())
        XCTAssertFalse(state.selectAllVisible())
        XCTAssertEqual(state.actionSelectedIDs, ["c"])
        XCTAssertEqual(state.focusedID, "c")
    }

    func testEscapeIsBlockedWhenSearchOwnsFocus() {
        var state = state()
        state.focus("c")
        state.actionSelectedIDs = ["c"]
        state.focusOwner = .search

        XCTAssertFalse(state.clearSelection())
        XCTAssertEqual(state.actionSelectedIDs, ["c"])
    }
}
