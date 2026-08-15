import AppKit
import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// Phase 4: contact-sheet geometry and Grid keyboard navigation.
///
/// Rubber-band selection is deliberately absent; it was dropped on 2026-08-15 in favour of
/// Shift/Command/keyboard selection.
final class MediaGridLayoutTests: XCTestCase {
    // MARK: - Column count

    func testColumnCountFitsAsManyWholeItemsAsPossible() {
        // 600 wide, 12 inset each side, 100 item + 10 spacing => floor(576/110) = 5
        let columns = MediaGridLayout.columnCount(
            availableWidth: 600,
            itemWidth: 100,
            spacing: 10,
            sectionInset: 12
        )
        XCTAssertEqual(columns, 5)
    }

    func testColumnCountIsAtLeastOneInANarrowViewport() {
        XCTAssertEqual(
            MediaGridLayout.columnCount(availableWidth: 40, itemWidth: 200, spacing: 10, sectionInset: 12),
            1
        )
    }

    func testColumnCountHandlesZeroAndNegativeWidth() {
        XCTAssertEqual(
            MediaGridLayout.columnCount(availableWidth: 0, itemWidth: 100, spacing: 10, sectionInset: 12),
            1
        )
        XCTAssertEqual(
            MediaGridLayout.columnCount(availableWidth: -50, itemWidth: 100, spacing: 10, sectionInset: 12),
            1
        )
    }

    func testColumnCountGrowsWithAvailableWidth() {
        let narrow = MediaGridLayout.columnCount(availableWidth: 400, itemWidth: 100, spacing: 10, sectionInset: 12)
        let wide = MediaGridLayout.columnCount(availableWidth: 1_200, itemWidth: 100, spacing: 10, sectionInset: 12)
        XCTAssertGreaterThan(wide, narrow)
    }

    func testColumnCountShrinksWhenItemsGetLarger() {
        let small = MediaGridLayout.columnCount(availableWidth: 800, itemWidth: 80, spacing: 10, sectionInset: 12)
        let large = MediaGridLayout.columnCount(availableWidth: 800, itemWidth: 240, spacing: 10, sectionInset: 12)
        XCTAssertLessThan(large, small)
    }

    // MARK: - No overlap

    /// The reported defect: tiles visibly overlapped at some widths and densities.
    /// The computed row width must never exceed the space actually available.
    func testItemsNeverOverlapAcrossManyWidthsAndDensities() {
        let inset: CGFloat = 12
        let spacing: CGFloat = 10

        for width in stride(from: 200.0, through: 2_000.0, by: 37.0) {
            for itemWidth in stride(from: 60.0, through: 320.0, by: 13.0) {
                let columns = MediaGridLayout.columnCount(
                    availableWidth: width,
                    itemWidth: itemWidth,
                    spacing: spacing,
                    sectionInset: inset
                )
                let usedWidth = CGFloat(columns) * itemWidth + CGFloat(columns - 1) * spacing
                let contentWidth = width - inset * 2

                // A single column is allowed to exceed a very narrow viewport; anything
                // more than one column must genuinely fit.
                if columns > 1 {
                    XCTAssertLessThanOrEqual(
                        usedWidth,
                        contentWidth + 0.5,
                        "columns=\(columns) overflow at width=\(width) itemWidth=\(itemWidth)"
                    )
                }
            }
        }
    }

    func testItemSizeIsNeverZeroOrNegative() {
        for scale in [0.75, 1.0, 1.6] {
            let size = MediaGridLayout.itemSize(thumbnailHeight: MediaDisplayScale(rawValue: scale).gridThumbnailHeight)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    func testItemHeightLeavesRoomForBothTextLines() {
        let thumbnailHeight: CGFloat = 120
        let size = MediaGridLayout.itemSize(thumbnailHeight: thumbnailHeight)
        XCTAssertGreaterThan(
            size.height,
            thumbnailHeight,
            "the tile must be taller than its thumbnail to fit the name and size labels"
        )
    }

    /// Regression: the reported item size must equal exactly what the tile's constraints
    /// produce. The first attempt sized the cell but left the thumbnail without a height
    /// constraint, so each image sized its own tile and the tiles overlapped.
    func testReportedItemHeightMatchesTheConstraintChainExactly() {
        for thumbnailHeight in stride(from: 60.0, through: 300.0, by: 7.0) {
            let size = MediaGridLayout.itemSize(thumbnailHeight: thumbnailHeight)
            let constraintChain = (
                MediaGridLayout.tilePadding                 // top padding
                + CGFloat(thumbnailHeight).rounded()        // fixed thumbnail square
                + MediaGridLayout.thumbnailToNameGap
                + MediaGridLayout.nameLabelHeight
                + MediaGridLayout.nameToSizeGap
                + MediaGridLayout.sizeLabelHeight
                + MediaGridLayout.tilePadding               // bottom padding
            ).rounded()

            XCTAssertEqual(
                size.height,
                constraintChain,
                "cell height must match the constraints at thumbnailHeight=\(thumbnailHeight)"
            )
        }
    }

    func testCaptionHeightIsTheSumOfItsParts() {
        XCTAssertEqual(
            MediaGridLayout.captionHeight,
            MediaGridLayout.thumbnailToNameGap
                + MediaGridLayout.nameLabelHeight
                + MediaGridLayout.nameToSizeGap
                + MediaGridLayout.sizeLabelHeight
        )
    }

    func testItemWidthIsThumbnailPlusBothPaddings() {
        let size = MediaGridLayout.itemSize(thumbnailHeight: 100)
        XCTAssertEqual(size.width, 100 + MediaGridLayout.tilePadding * 2)
    }
}

@MainActor
final class MediaGridInteractionTests: XCTestCase {
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

    private func viewModel(_ ids: [String] = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = ids.map { item($0) }
        viewModel.sortField = .name
        viewModel.sortOrder = .ascending
        viewModel.refreshVisibleOrder()
        viewModel.setFocusOwner(.mediaBrowser)
        return viewModel
    }

    // MARK: - Four-direction navigation

    func testRightArrowMovesOneItem() {
        let viewModel = viewModel()
        viewModel.select(item("a"))

        viewModel.moveFocus(rows: 0, columns: 1, columnCount: 3, extendingSelection: false)

        XCTAssertEqual(viewModel.selectedItemID, "b")
    }

    func testDownArrowMovesByTheMeasuredColumnCount() {
        let viewModel = viewModel()
        viewModel.select(item("a"))

        viewModel.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false)

        XCTAssertEqual(viewModel.selectedItemID, "d")
    }

    func testUpArrowMovesBackByTheColumnCount() {
        let viewModel = viewModel()
        viewModel.select(item("h"))

        viewModel.moveFocus(rows: -1, columns: 0, columnCount: 3, extendingSelection: false)

        XCTAssertEqual(viewModel.selectedItemID, "e")
    }

    func testNavigationClampsAtTheLastItem() {
        let viewModel = viewModel()
        viewModel.select(item("i"))

        viewModel.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false)

        XCTAssertEqual(viewModel.selectedItemID, "i")
    }

    func testArrowNavigationDoesNotChangeActionSelection() {
        let viewModel = viewModel()
        viewModel.select(item("a"))

        viewModel.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: false)
        viewModel.moveFocus(rows: 0, columns: 1, columnCount: 3, extendingSelection: false)

        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testContextMenuUsesDownloadForTheTransferAction() {
        let viewModel = viewModel(["a"])
        let coordinator = MediaCollectionView.Coordinator(viewModel: viewModel)
        coordinator.apply(items: viewModel.filteredItems)

        let titles = coordinator.contextMenu(forIndex: 0)?.items.map(\.title)

        XCTAssertEqual(titles, ["Select", "", "Download “a.heic”", "Delete “a.heic”"])
    }

    // MARK: - Shift extension (the chosen multi-select gesture)

    func testShiftDownExtendsAcrossAWholeRow() {
        let viewModel = viewModel()
        viewModel.select(item("a"))

        viewModel.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedActionIDs, ["a", "b", "c", "d"])
    }

    func testShiftRightExtendsOneItemAtATime() {
        let viewModel = viewModel()
        viewModel.select(item("a"))

        viewModel.moveFocus(rows: 0, columns: 1, columnCount: 3, extendingSelection: true)
        viewModel.moveFocus(rows: 0, columns: 1, columnCount: 3, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedActionIDs, ["a", "b", "c"])
    }

    func testShiftExtensionShrinksWhenReversing() {
        let viewModel = viewModel()
        viewModel.select(item("a"))
        viewModel.moveFocus(rows: 1, columns: 0, columnCount: 3, extendingSelection: true)
        XCTAssertEqual(viewModel.selectedActionIDs.count, 4)

        viewModel.moveFocus(rows: -1, columns: 0, columnCount: 3, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedActionIDs, ["a"])
    }

    // MARK: - View mode reset

    /// Reported defect: switching List to Grid carried the other renderer's state across.
    func testSwitchingViewModeClearsCarriedOverInteractionState() {
        let viewModel = viewModel()
        viewModel.select(item("d"))
        viewModel.toggleActionSelection(item("d"))
        viewModel.toggleActionSelection(item("e"))

        viewModel.setViewMode(.grid)

        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    func testSwitchingViewModePublishesAFreshVisibleOrder() {
        let viewModel = viewModel()
        viewModel.setViewMode(.grid)

        XCTAssertEqual(viewModel.selection.visibleIDs.count, 9)
    }

    func testSwitchingToTheSameViewModeIsANoOp() {
        let viewModel = viewModel()
        viewModel.select(item("d"))
        viewModel.toggleActionSelection(item("d"))

        viewModel.setViewMode(.list)

        XCTAssertEqual(viewModel.selectedItemID, "d")
        XCTAssertEqual(viewModel.selectedActionIDs, ["d"])
    }

    // MARK: - Shared contract still applies in Grid

    func testCommandASelectsAllVisibleInGrid() {
        let viewModel = viewModel()
        viewModel.setViewMode(.grid)
        viewModel.setFocusOwner(.mediaBrowser)

        viewModel.selectAllVisible()

        XCTAssertEqual(viewModel.selectedActionIDs.count, 9)
    }

    func testEscapeClearsGridSelectionWithoutHidingInspector() {
        let viewModel = viewModel()
        viewModel.select(item("c"))
        viewModel.toggleActionSelection(item("c"))

        XCTAssertTrue(viewModel.clearSelection())
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
        XCTAssertTrue(viewModel.isInspectorVisible)
    }
}
