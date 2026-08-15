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
}
