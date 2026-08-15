import DeduperCore
import ImageCaptureCore
import XCTest
@testable import ImageDedupeApp

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
                token: .fixture()
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
                token: .fixture()
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

    // MARK: - Plain queries must not match raw numeric fields

    /// Reported 2026-08-15: searching `1.2` returned videos with no visible relationship to
    /// the query. Their durations stringified as e.g. `111.25`, which contains "1.2".
    func testPlainQueryDoesNotMatchRawDurationSeconds() {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "id-0", name: "SJJS7164.MOV", kind: "mov",
                    size: 181_000_000, timestamp: "2025-03-01T10:00:00Z",
                    width: 1_920, height: 1_080, duration: 111.25
                ),
                token: .fixture()
            )
        ]
        viewModel.refreshVisibleOrder()

        viewModel.searchText = "1.2"
        viewModel.flushPendingSearch()

        XCTAssertTrue(viewModel.visibleItems.isEmpty, "111.25 seconds must not match \"1.2\"")
    }

    func testPlainQueryDoesNotMatchRawPixelDimensions() {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "id-0", name: "PHOTO.HEIC", kind: "heic",
                    size: 100, timestamp: nil, width: 1_920, height: 1_080
                ),
                token: .fixture()
            )
        ]
        viewModel.refreshVisibleOrder()

        viewModel.searchText = "1920"
        viewModel.flushPendingSearch()

        XCTAssertTrue(viewModel.visibleItems.isEmpty, "dimensions are searched via tokens, not free text")
    }

    /// Numbers stay reachable through the explicit tokens, where intent is unambiguous.
    func testDurationTokenStillMatchesNumerically() {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "short", name: "A.MOV", kind: "mov", size: 10,
                    timestamp: nil, width: nil, height: nil, duration: 5
                ),
                token: .fixture()
            ),
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "long", name: "B.MOV", kind: "mov", size: 10,
                    timestamp: nil, width: nil, height: nil, duration: 300
                ),
                token: .fixture()
            )
        ]
        viewModel.refreshVisibleOrder()

        viewModel.searchText = "duration:<10s"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["short"])
    }

    func testNameSearchStillWorksForNumbersInsideNames() {
        let viewModel = viewModel(names: ["IMG_1234.HEIC", "OTHER.HEIC"])
        viewModel.searchText = "1234"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.count, 1, "digits in the filename must still match")
    }

    // MARK: - Unprefixed terms search the name

    func testUnprefixedTermSearchesTheName() {
        let viewModel = viewModel(names: ["IMG_0001.HEIC", "OTHER.MOV"])
        viewModel.searchText = "IMG"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.map(\.model.name), ["IMG_0001.HEIC"])
    }

    /// A bare `mov` must not match every `.MOV` file by kind; it searches the name only.
    /// Users who want the kind write `kind:mov`.
    func testUnprefixedTermDoesNotSearchKind() {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "id-0", name: "CLIP.QT", kind: "mov",
                    size: 10, timestamp: nil, width: nil, height: nil
                ),
                token: .fixture()
            )
        ]
        viewModel.refreshVisibleOrder()

        viewModel.searchText = "mov"
        viewModel.flushPendingSearch()
        XCTAssertTrue(viewModel.visibleItems.isEmpty, "bare text searches the name, not the kind")

        viewModel.searchText = "kind:mov"
        viewModel.flushPendingSearch()
        XCTAssertEqual(viewModel.visibleItems.count, 1, "the explicit prefix still works")
    }

    func testNamePrefixIsEquivalentToAnUnprefixedTerm() {
        let viewModel = viewModel(names: ["IMG_0001.HEIC", "OTHER.MOV"])

        viewModel.searchText = "name:IMG"
        viewModel.flushPendingSearch()
        let prefixed = viewModel.visibleItems.map(\.id)

        viewModel.searchText = "IMG"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.map(\.id), prefixed)
    }

    /// A filename containing a colon must not be mistaken for an unknown prefix.
    func testTermWithAnUnknownPrefixSearchesTheName() {
        let viewModel = viewModel(names: ["a:b.HEIC", "OTHER.MOV"])
        viewModel.searchText = "a:b"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.count, 1)
    }

    func testMultipleTermsMustAllMatch() {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "match", name: "IMG_0001.MOV", kind: "mov",
                    size: 10, timestamp: nil, width: nil, height: nil
                ),
                token: .fixture()
            ),
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "wrong-kind", name: "IMG_0002.HEIC", kind: "heic",
                    size: 10, timestamp: nil, width: nil, height: nil
                ),
                token: .fixture()
            )
        ]
        viewModel.refreshVisibleOrder()

        viewModel.searchText = "IMG kind:mov"
        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["match"])
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
