import XCTest

@testable import DeduperCore

/// Scanning while the iPhone is locked.
///
/// Reported on 2026-08-15: pressing Scan with the phone locked appeared to freeze the app,
/// and only relaunching recovered it. ImageCaptureCore answers `requestOpenSession` with
/// error -9943 "Please unlock ..." and the gateway retries, which is right — the user may
/// unlock a moment later — but the retry had no limit, so the scan sat until its full
/// timeout with nothing on screen explaining why.
final class LockedDeviceGuidanceTests: XCTestCase {
    func testUnlockErrorsAreRetryable() {
        XCTAssertTrue(OpenSessionRetry.shouldRetry(
            domain: "com.apple.ImageCaptureCore",
            code: -9943,
            description: "Please unlock “shuqi's iPhone”"
        ))
    }

    func testUnrelatedErrorsAreNotRetried() {
        XCTAssertFalse(OpenSessionRetry.shouldRetry(
            domain: "com.apple.ImageCaptureCore",
            code: -9934,
            description: "Some other failure"
        ))
        XCTAssertFalse(OpenSessionRetry.shouldRetry(
            domain: "NSCocoaErrorDomain",
            code: -9943,
            description: "Please unlock"
        ))
    }

    /// Retrying must stop. Waiting out a 180-second timeout with no explanation is what
    /// read as a freeze; a bounded wait can report something useful instead.
    func testRetriesAreBounded() {
        XCTAssertGreaterThan(OpenSessionRetry.maximumAttempts, 1, "One try is not a retry.")
        XCTAssertLessThanOrEqual(
            OpenSessionRetry.maximumAttempts,
            30,
            "The user should not wait minutes to be told to unlock their phone."
        )
    }

    func testAttemptsAreExhaustedAfterTheLimit() {
        XCTAssertTrue(OpenSessionRetry.shouldRetry(
            domain: "com.apple.ImageCaptureCore",
            code: -9943,
            description: "Please unlock",
            attempt: OpenSessionRetry.maximumAttempts - 1
        ))
        XCTAssertFalse(
            OpenSessionRetry.shouldRetry(
                domain: "com.apple.ImageCaptureCore",
                code: -9943,
                description: "Please unlock",
                attempt: OpenSessionRetry.maximumAttempts
            ),
            "Past the limit the scan must fail with guidance rather than retry forever."
        )
    }

    /// The message the user sees must say what to do, not what failed internally.
    func testTheLockedDeviceMessageTellsTheUserWhatToDo() {
        let advice = DeviceRecoveryAdvice.forFailure(
            "framework(\"Could not open ImageCaptureCore session: Please unlock “shuqi's iPhone”\")"
        )
        XCTAssertEqual(
            advice.kind,
            .deviceLocked,
            "ImageCaptureCore says \"Please unlock\", not \"locked\", and that wording used to "
                + "fall through to the generic failure, leaving the user with no guidance."
        )
    }
}
