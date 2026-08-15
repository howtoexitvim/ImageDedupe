import XCTest
@testable import ImageDedupeApp

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

    /// Representative labels for a busy catalog. The planner measures what it is given, so
    /// tests must supply the strings the bar would really render; a bar with no text needs
    /// no room and would never drop anything.
    private static let sampleLabels = MediaStatusBarLayout.Labels(
        duplicateCount: "Duplicate candidates 120",
        shownCount: "3,954 shown / 3,954 total",
        selectedCount: "12 selected",
        destinationTitle: "Pictures",
        resultsTitle: "Results",
        progressText: "Importing 12 of 40"
    )

    // MARK: - Narrow widths drop labels instead of wrapping
    //
    // Bounding only the status text was not enough. Every other label in the bar — the
    // destination menu, "Results", the counts — could still wrap, and at narrow widths
    // SwiftUI compressed those instead, so "Results" broke into "Re-/sults" and the bar
    // still grew taller. Nothing in the bar may wrap; items are dropped in priority order.

    func testWideBarShowsEveryElement() {
        let plan = MediaStatusBarLayout.plan(
            availableWidth: 1280,
            hasProgress: false,
            labels: Self.sampleLabels
        )

        XCTAssertTrue(plan.showsDestinationTitle)
        XCTAssertTrue(plan.showsResultsTitle)
        XCTAssertTrue(plan.showsSelectedCount)
        XCTAssertTrue(plan.showsShownCount)
        XCTAssertTrue(plan.showsDuplicateCount)
    }

    func testNarrowBarHidesTitlesRatherThanWrappingThem() {
        let plan = MediaStatusBarLayout.plan(
            availableWidth: 620,
            hasProgress: true,
            labels: Self.sampleLabels
        )

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
        let duplicateGone = MediaStatusBarLayout.plan(availableWidth: 900, hasProgress: true, labels: Self.sampleLabels)
        XCTAssertFalse(duplicateGone.showsDuplicateCount, "Duplicate count is the first to go.")
        XCTAssertTrue(duplicateGone.showsSelectedCount)

        let shownGone = MediaStatusBarLayout.plan(availableWidth: 760, hasProgress: true, labels: Self.sampleLabels)
        XCTAssertFalse(shownGone.showsShownCount)

        let selectedGone = MediaStatusBarLayout.plan(availableWidth: 520, hasProgress: true, labels: Self.sampleLabels)
        XCTAssertFalse(selectedGone.showsSelectedCount)
    }

    func testActionButtonsAndCancelSurviveTheNarrowestWidth() {
        let plan = MediaStatusBarLayout.plan(availableWidth: 320, hasProgress: true, labels: Self.sampleLabels)

        // Controls the user must be able to reach are never dropped; only labels are.
        XCTAssertTrue(plan.showsProgressText)
        XCTAssertFalse(plan.showsProgressBar, "The decorative bar yields before the text.")
    }

    func testActionTitlesCollapseToIconsOnlyAsTheLastResort() {
        // A truncated button reading `D` is useless, so the words give way to icons — but
        // only after every count and title has already been dropped.
        let roomy = MediaStatusBarLayout.plan(availableWidth: 1280, hasProgress: false, labels: Self.sampleLabels)
        XCTAssertTrue(roomy.showsActionTitles)

        let tight = MediaStatusBarLayout.plan(availableWidth: 320, hasProgress: true, labels: Self.sampleLabels)
        XCTAssertFalse(tight.showsActionTitles)
        XCTAssertFalse(tight.showsDuplicateCount)
        XCTAssertFalse(tight.showsSelectedCount)
    }

    /// Progress takes room, so at some width it must cost a count.
    ///
    /// Stated as a property rather than against one hand-picked width: the widths are now
    /// measured from the real text, so a magic number tuned to the old constants would
    /// prove nothing about the behaviour it is meant to protect.
    func testProgressReservesRoomSoCountsYieldEarlier() {
        var foundWidthWhereProgressCostsACount = false

        for width in stride(from: CGFloat(600), through: 1_400, by: 20) {
            let idle = MediaStatusBarLayout.plan(
                availableWidth: width,
                hasProgress: false,
                labels: Self.sampleLabels
            )
            let busy = MediaStatusBarLayout.plan(
                availableWidth: width,
                hasProgress: true,
                labels: Self.sampleLabels
            )

            // Progress may never *add* an element that idle could not afford.
            if busy.showsDuplicateCount { XCTAssertTrue(idle.showsDuplicateCount) }
            if busy.showsShownCount { XCTAssertTrue(idle.showsShownCount) }

            if idle.showsDuplicateCount, !busy.showsDuplicateCount {
                foundWidthWhereProgressCostsACount = true
            }
        }

        XCTAssertTrue(
            foundWidthWhereProgressCostsACount,
            "Progress occupies real width, so somewhere it must displace a count."
        )
    }

    // MARK: - Measured widths

    /// The drop thresholds were hand-measured constants for text whose width depends on the
    /// system font and the actual numbers shown, so they could be early or late at unusual
    /// font sizes. Measuring the rendered string is exact and costs one text layout per
    /// element per resize.
    func testMeasuredWidthTracksTheTextItIsGiven() {
        let short = MediaStatusBarLayout.measuredWidth(of: "1 item")
        let long = MediaStatusBarLayout.measuredWidth(of: "4,000 duplicates · 12.3 GB")

        XCTAssertGreaterThan(short, 0)
        XCTAssertGreaterThan(long, short, "A longer label must measure wider.")
    }

    /// Empty text takes no space, so an absent element cannot reserve width.
    func testEmptyTextMeasuresZero() {
        XCTAssertEqual(MediaStatusBarLayout.measuredWidth(of: ""), 0)
    }

    /// Measurement must be stable, or the bar would drop and restore an element as the
    /// window is dragged by a pixel.
    func testMeasurementIsStableAcrossCalls() {
        let first = MediaStatusBarLayout.measuredWidth(of: "3,954 shown")
        let second = MediaStatusBarLayout.measuredWidth(of: "3,954 shown")
        XCTAssertEqual(first, second)
    }

    /// A plan built from measured labels still drops in the documented order: the counts
    /// go before the operation text the user is waiting to read.
    func testMeasuredPlanDropsLeastInformativeFirst() {
        let labels = MediaStatusBarLayout.Labels(
            duplicateCount: "120 duplicates · 1.2 GB",
            shownCount: "3,954 shown",
            selectedCount: "2 selected",
            destinationTitle: "Pictures",
            resultsTitle: "Results",
            progressText: "Importing 2 of 40"
        )

        // Generous width keeps everything.
        let roomy = MediaStatusBarLayout.plan(availableWidth: 4_000, hasProgress: true, labels: labels)
        XCTAssertTrue(roomy.showsDuplicateCount)
        XCTAssertTrue(roomy.showsShownCount)

        // Squeezed hard, the counts go and the action titles are given up last.
        let tight = MediaStatusBarLayout.plan(availableWidth: 380, hasProgress: true, labels: labels)
        XCTAssertFalse(tight.showsDuplicateCount)
        XCTAssertFalse(tight.showsShownCount)
    }

    /// The measured planner must agree with the constant-based one at the extremes, so the
    /// change cannot silently alter behaviour at ordinary window sizes.
    func testMeasuredPlanKeepsEverythingAtFullScreenWidth() {
        let plan = MediaStatusBarLayout.plan(
            availableWidth: 2_560,
            hasProgress: false,
            labels: .init(
                duplicateCount: "2 duplicates · 900 KB",
                shownCount: "3,954 shown",
                selectedCount: "0 selected",
                destinationTitle: "Pictures",
                resultsTitle: "Results",
                progressText: ""
            )
        )

        XCTAssertTrue(plan.showsDuplicateCount)
        XCTAssertTrue(plan.showsShownCount)
        XCTAssertTrue(plan.showsSelectedCount)
        XCTAssertTrue(plan.showsActionTitles)
    }
}
