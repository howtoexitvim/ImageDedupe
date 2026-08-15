import XCTest
@testable import DeduperCore

/// Phase 7: failures tell the user what to do next.
///
/// Reported 2026-08-15: the iPhone auto-locked partway through a scan, ImageCaptureCore
/// refused the session, and the app surfaced that as one line of truncated status text.
/// The user could not tell a locked phone from a broken app.
final class DeviceRecoveryAdviceTests: XCTestCase {
    func testLockedDeviceIsRecognisedAndExplained() {
        let advice = DeviceRecoveryAdvice.forFailure("device is locked or access restricted")

        XCTAssertEqual(advice.kind, .deviceLocked)
        XCTAssertFalse(advice.title.isEmpty)
        XCTAssertFalse(advice.steps.isEmpty, "a locked device must come with instructions")
    }

    /// The specific thing that bit the user: a long scan outlives the auto-lock timer.
    func testLockedAdviceMentionsKeepingTheScreenAwake() {
        let advice = DeviceRecoveryAdvice.forFailure("locked")
        let joined = advice.steps.joined(separator: " ").lowercased()

        XCTAssertTrue(joined.contains("auto-lock") || joined.contains("awake"), joined)
    }

    func testLockedAdviceMentionsTrustingTheMac() {
        let advice = DeviceRecoveryAdvice.forFailure("access restricted")
        let joined = advice.steps.joined(separator: " ").lowercased()

        XCTAssertTrue(joined.contains("trust"), joined)
    }

    func testNoDeviceIsDistinctFromLocked() {
        let advice = DeviceRecoveryAdvice.forFailure("No ImageCaptureCore camera device found.")

        XCTAssertEqual(advice.kind, .noDevice)
        XCTAssertFalse(advice.steps.isEmpty)
    }

    /// Image Capture and Photos take the device session exclusively.
    func testSessionConflictIsRecognised() {
        let advice = DeviceRecoveryAdvice.forFailure("could not open session: device is busy")

        XCTAssertEqual(advice.kind, .sessionConflict)
        let joined = advice.steps.joined(separator: " ").lowercased()
        XCTAssertTrue(joined.contains("image capture") || joined.contains("photos"), joined)
    }

    func testTimeoutIsRecognised() {
        let advice = DeviceRecoveryAdvice.forFailure("timed out waiting for device")
        XCTAssertEqual(advice.kind, .timeout)
    }

    func testDisconnectIsRecognised() {
        let advice = DeviceRecoveryAdvice.forFailure("device was disconnected")
        XCTAssertEqual(advice.kind, .disconnected)
    }

    /// An unrecognised failure must still produce something actionable rather than a bare
    /// error dump.
    func testUnknownFailureStillOffersGeneralSteps() {
        let advice = DeviceRecoveryAdvice.forFailure("something entirely unexpected")

        XCTAssertEqual(advice.kind, .unknown)
        XCTAssertFalse(advice.steps.isEmpty)
        XCTAssertTrue(
            advice.detail.contains("something entirely unexpected"),
            "the original message must be preserved for diagnosis"
        )
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(DeviceRecoveryAdvice.forFailure("DEVICE IS LOCKED").kind, .deviceLocked)
    }

    func testEveryKindHasATitleAndSteps() {
        for kind in DeviceRecoveryAdvice.Kind.allCases {
            let advice = DeviceRecoveryAdvice(kind: kind, detail: "")
            XCTAssertFalse(advice.title.isEmpty, "\(kind) needs a title")
            XCTAssertFalse(advice.steps.isEmpty, "\(kind) needs at least one step")
        }
    }

    /// The status bar truncates, so the one-line summary has to stay short while the full
    /// steps live in the detailed presentation.
    func testSummaryIsShortEnoughForTheStatusBar() {
        for kind in DeviceRecoveryAdvice.Kind.allCases {
            let advice = DeviceRecoveryAdvice(kind: kind, detail: "")
            XCTAssertLessThanOrEqual(advice.title.count, 60, "\(kind): \(advice.title)")
        }
    }
}
