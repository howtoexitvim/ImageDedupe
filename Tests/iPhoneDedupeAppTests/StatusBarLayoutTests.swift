import XCTest
@testable import iPhoneDedupeApp

/// A long idle status such as the pending-verification message used to expand the bottom
/// status area vertically. The variable label now has a bounded, single-line region while
/// the count labels stay visible and the full text stays reachable via Help/VoiceOver.
final class StatusBarLayoutTests: XCTestCase {
    private let longStatus = "Delete finished, but verification is pending. Open Results to retry verification."

    func testLongStatusIsSingleLineAndTailTruncated() {
        let label = MediaStatusBarText(message: longStatus)

        XCTAssertEqual(label.lineLimit, 1)
        XCTAssertEqual(label.truncation, .tail)
    }

    func testFullMessageRemainsAvailableToHelpAndVoiceOver() {
        let label = MediaStatusBarText(message: longStatus)

        XCTAssertEqual(label.help, longStatus, "Help must carry the untruncated message.")
        XCTAssertTrue(
            label.accessibilityLabel.contains(longStatus),
            "VoiceOver must read the untruncated message."
        )
    }

    func testVariableRegionIsBoundedSoCountsAreNeverSwallowed() {
        let label = MediaStatusBarText(message: longStatus)

        XCTAssertNotNil(label.maximumWidth, "An unbounded label pushes the count labels out.")
        XCTAssertGreaterThan(label.minimumWidth, 0)
        XCTAssertGreaterThan(label.maximumWidth ?? 0, label.minimumWidth)
    }

    func testShortStatusUsesTheSameSingleLineContract() {
        let label = MediaStatusBarText(message: "Idle")

        XCTAssertEqual(label.lineLimit, 1)
        XCTAssertEqual(label.help, "Idle")
    }

    // MARK: - Narrow widths drop labels instead of wrapping
    //
    // Bounding only the status text was not enough. Every other label in the bar — the
    // destination menu, "Results", the counts — could still wrap, and at narrow widths
    // SwiftUI compressed those instead, so "Results" broke into "Re-/sults" and the bar
    // still grew taller. Nothing in the bar may wrap; items are dropped in priority order.

    func testWideBarShowsEveryElement() {
        let plan = MediaStatusBarLayout.plan(availableWidth: 1280, hasProgress: false)

        XCTAssertTrue(plan.showsDestinationTitle)
        XCTAssertTrue(plan.showsResultsTitle)
        XCTAssertTrue(plan.showsSelectedCount)
        XCTAssertTrue(plan.showsShownCount)
        XCTAssertTrue(plan.showsDuplicateCount)
    }

    func testNarrowBarHidesTitlesRatherThanWrappingThem() {
        let plan = MediaStatusBarLayout.plan(availableWidth: 620, hasProgress: true)

        XCTAssertFalse(
            plan.showsResultsTitle,
            "`Results` must collapse to its icon rather than wrap to two lines."
        )
        XCTAssertFalse(
            plan.showsDestinationTitle,
            "The destination name must collapse to its folder icon."
        )
    }

    func testCountsDropInPriorityOrderAsWidthShrinks() {
        let duplicateGone = MediaStatusBarLayout.plan(availableWidth: 900, hasProgress: true)
        XCTAssertFalse(duplicateGone.showsDuplicateCount, "Duplicate count is the first to go.")
        XCTAssertTrue(duplicateGone.showsSelectedCount)

        let shownGone = MediaStatusBarLayout.plan(availableWidth: 760, hasProgress: true)
        XCTAssertFalse(shownGone.showsShownCount)

        let selectedGone = MediaStatusBarLayout.plan(availableWidth: 520, hasProgress: true)
        XCTAssertFalse(selectedGone.showsSelectedCount)
    }

    func testActionButtonsAndCancelSurviveTheNarrowestWidth() {
        let plan = MediaStatusBarLayout.plan(availableWidth: 320, hasProgress: true)

        // Controls the user must be able to reach are never dropped; only labels are.
        XCTAssertTrue(plan.showsProgressText)
        XCTAssertFalse(plan.showsProgressBar, "The decorative bar yields before the text.")
    }

    func testProgressReservesRoomSoCountsYieldEarlier() {
        // At a width that fits everything when idle, the progress bar and its text push the
        // lowest-priority count out.
        let width: CGFloat = 1_120
        let withoutProgress = MediaStatusBarLayout.plan(availableWidth: width, hasProgress: false)
        let withProgress = MediaStatusBarLayout.plan(availableWidth: width, hasProgress: true)

        XCTAssertTrue(withoutProgress.showsDuplicateCount)
        XCTAssertFalse(withProgress.showsDuplicateCount)
    }
}
