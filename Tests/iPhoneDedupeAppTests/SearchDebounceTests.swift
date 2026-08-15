import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// Phase 6: search is debounced so a 4,000-item derivation does not run per keystroke.
///
/// Typing must stay immediate — `searchText` is bound straight to the field — while the
/// expensive filter trails behind it in `appliedSearchText`.
@MainActor
final class SearchDebounceTests: XCTestCase {
    private func viewModel(count: Int = 200) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = (0..<count).map { index in
            MediaBrowserViewModel.MediaItem(
                model: DeviceMediaFile(
                    id: "id-\(index)",
                    name: String(format: "IMG_%04d.HEIC", index),
                    kind: "heic",
                    size: 1_000,
                    timestamp: nil,
                    width: nil,
                    height: nil
                ),
                token: .fixture()
            )
        }
        viewModel.refreshVisibleOrder()
        return viewModel
    }

    /// Waits comfortably longer than the debounce interval.
    private func waitForDebounce() async {
        try? await Task.sleep(for: MediaBrowserViewModel.searchDebounceInterval * 3)
    }

    func testTypingUpdatesTheFieldImmediately() {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0007"

        XCTAssertEqual(viewModel.searchText, "IMG_0007", "the field must never lag the user")
    }

    func testTheQueryIsNotAppliedImmediately() {
        let viewModel = viewModel()
        let before = viewModel.catalogDerivationCount

        viewModel.searchText = "IMG_0007"

        XCTAssertEqual(viewModel.appliedSearchText, "", "the filter waits for the pause")
        XCTAssertEqual(viewModel.catalogDerivationCount, before, "no derivation per keystroke")
    }

    func testTheQueryIsAppliedAfterThePause() async {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0007"

        await waitForDebounce()

        XCTAssertEqual(viewModel.appliedSearchText, "IMG_0007")
        XCTAssertEqual(viewModel.visibleItems.map(\.model.name), ["IMG_0007.HEIC"])
    }

    /// The point of the debounce: typing a word runs one derivation, not one per character.
    func testTypingAWordDerivesTheCatalogOnce() async {
        let viewModel = viewModel()
        _ = viewModel.visibleItems
        let before = viewModel.catalogDerivationCount

        for prefix in ["I", "IM", "IMG", "IMG_", "IMG_0", "IMG_00", "IMG_000", "IMG_0007"] {
            viewModel.searchText = prefix
        }
        await waitForDebounce()
        _ = viewModel.visibleItems

        XCTAssertEqual(
            viewModel.catalogDerivationCount - before,
            1,
            "eight keystrokes must collapse into one derivation"
        )
    }

    func testASupersededQueryIsNeverApplied() async {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0001"
        viewModel.searchText = "IMG_0002"
        viewModel.searchText = "IMG_0003"

        await waitForDebounce()

        XCTAssertEqual(viewModel.appliedSearchText, "IMG_0003", "only the last query survives")
    }

    func testClearingSearchIsAlsoDebouncedAndApplied() async {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0007"
        await waitForDebounce()
        XCTAssertEqual(viewModel.visibleItems.count, 1)

        viewModel.searchText = ""
        await waitForDebounce()

        XCTAssertEqual(viewModel.visibleItems.count, 200)
    }

    func testFlushAppliesThePendingQueryWithoutWaiting() {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0007"

        viewModel.flushPendingSearch()

        XCTAssertEqual(viewModel.appliedSearchText, "IMG_0007")
        XCTAssertEqual(viewModel.visibleItems.count, 1)
    }

    func testFlushingTwiceDoesNotRederive() {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0007"
        viewModel.flushPendingSearch()
        _ = viewModel.visibleItems
        let after = viewModel.catalogDerivationCount

        viewModel.flushPendingSearch()
        _ = viewModel.visibleItems

        XCTAssertEqual(viewModel.catalogDerivationCount, after)
    }

    /// A flush must cancel the pending timer, or the stale query would land afterwards.
    func testFlushCancelsThePendingApply() async {
        let viewModel = viewModel()
        viewModel.searchText = "IMG_0007"
        viewModel.flushPendingSearch()

        await waitForDebounce()

        XCTAssertEqual(viewModel.appliedSearchText, "IMG_0007")
    }

    func testSelectionIsReconciledOnceTheQueryLands() async {
        let viewModel = viewModel(count: 10)
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectAllVisible()
        XCTAssertEqual(viewModel.selectedActionIDs.count, 10)

        viewModel.searchText = "IMG_0003"
        await waitForDebounce()

        XCTAssertEqual(viewModel.selectedActionIDs, ["id-3"])
    }
}
