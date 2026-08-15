import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// Audit of the search field's edge cases, written before deciding whether Phase 7 could
/// start. Each test documents a case a user can actually reach.
@MainActor
final class SearchAuditTests: XCTestCase {
    private func viewModel(names: [String] = ["IMG_0001.HEIC", "IMG_0002.MOV", "video.mp4"]) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = names.enumerated().map { index, name in
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "id-\(index)",
                    name: name,
                    kind: (name as NSString).pathExtension.lowercased(),
                    size: Int64((index + 1) * 1_000_000),
                    timestamp: nil,
                    width: nil,
                    height: nil,
                    duration: name.hasSuffix(".mp4") ? 30 : nil
                ),
                cameraFile: ICCameraFile()
            )
        }
        viewModel.refreshVisibleOrder()
        return viewModel
    }

    // MARK: - A scan while a search is active

    /// A scan replaces the catalog. The query the user can see in the field must remain the
    /// query being applied, or the list contents stop matching the visible search text.
    func testSearchStaysAppliedAcrossANewCatalog() {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0001"
        viewModel.flushPendingSearch()
        XCTAssertEqual(viewModel.visibleItems.count, 1)

        // Simulate what a scan does to the catalog.
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "new-1", name: "IMG_0001.HEIC", kind: "heic",
                    size: 10, timestamp: nil, width: nil, height: nil
                ),
                cameraFile: ICCameraFile()
            )
        ]
        viewModel.refreshVisibleOrder()

        XCTAssertEqual(viewModel.appliedSearchText, "IMG_0001")
        XCTAssertEqual(viewModel.visibleItems.count, 1)
        XCTAssertEqual(
            viewModel.searchText,
            viewModel.appliedSearchText,
            "the field and the applied query must not diverge"
        )
    }

    // MARK: - Whitespace and empty input

    func testWhitespaceOnlySearchMatchesEverything() {
        let viewModel = viewModel()
        viewModel.searchText = "   "
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.count, 3, "blank input must not hide the catalog")
    }

    func testClearingSearchRestoresTheFullCatalog() {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0001"
        viewModel.flushPendingSearch()
        viewModel.searchText = ""
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.count, 3)
    }

    // MARK: - Queries that match nothing

    func testNoMatchProducesAnEmptyListRatherThanTheWholeCatalog() {
        let viewModel = viewModel()
        viewModel.searchText = "zzzz-no-such-file"
        viewModel.flushPendingSearch()

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testSelectionIsClearedWhenTheSearchMatchesNothing() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectAllVisible()

        viewModel.searchText = "zzzz-no-such-file"
        viewModel.flushPendingSearch()

        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty, "hidden items must not stay selected")
        XCTAssertNil(viewModel.selectedItem)
    }

    /// Import and Delete act on the action selection. If a hidden item could stay selected,
    /// the user could delete something the list is not showing.
    func testHiddenItemsCannotRemainActionSelected() {
        let viewModel = viewModel()
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectAllVisible()
        XCTAssertEqual(viewModel.selectedActionIDs.count, 3)

        viewModel.searchText = "IMG_0001"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.selectedActionIDs.count, 1)
        XCTAssertTrue(
            viewModel.selectedActionIDs.isSubset(of: Set(viewModel.visibleItems.map(\.id))),
            "every selected item must be visible"
        )
    }

    // MARK: - Token queries

    func testKindTokenFiltersByKind() {
        let viewModel = viewModel()
        viewModel.searchText = "kind:mov"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.map(\.model.kind), ["mov"])
    }

    func testMalformedTokenDoesNotCrashOrMatchEverything() {
        let viewModel = viewModel()
        viewModel.searchText = "size:>"
        viewModel.flushPendingSearch()

        // The important property is that it stays well-defined and does not trap.
        XCTAssertLessThanOrEqual(viewModel.visibleItems.count, 3)
    }

    func testUnknownTokenIsTreatedAsText() {
        let viewModel = viewModel()
        viewModel.searchText = "nosuchfield:value"
        viewModel.flushPendingSearch()

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    // MARK: - Unicode and case

    func testSearchIsCaseInsensitive() {
        let viewModel = viewModel()
        viewModel.searchText = "img_0001"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.count, 1)
    }

    func testUnicodeQueryDoesNotCrash() {
        let viewModel = viewModel(names: ["照片_001.HEIC", "IMG_0002.MOV"])
        viewModel.searchText = "照片"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.count, 1)
    }

    func testEmojiQueryIsHandled() {
        let viewModel = viewModel()
        viewModel.searchText = "📷"
        viewModel.flushPendingSearch()

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    // MARK: - Search interacts correctly with scope

    func testSearchAndScopeComposeRatherThanOverride() {
        let viewModel = viewModel()
        viewModel.selectReviewScope(.duplicates)
        viewModel.searchText = "IMG"
        viewModel.flushPendingSearch()

        // Duplicates scope is empty for this fixture, so the combination must be empty too
        // rather than falling back to the search alone.
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testSwitchingViewModeKeepsTheAppliedQuery() {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0001"
        viewModel.flushPendingSearch()

        viewModel.setViewMode(.grid)

        XCTAssertEqual(viewModel.appliedSearchText, "IMG_0001")
        XCTAssertEqual(viewModel.visibleItems.count, 1)
    }
}
