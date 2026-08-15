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

    // MARK: - Giving up quickly when no device appears

    /// The real cause of the long wait reported on 2026-08-16.
    ///
    /// Bounding the unlock retry did not help. Callback tracing showed why, and corrected an
    /// earlier guess of mine that the device was simply never advertised:
    ///
    /// ```text
    /// TRACE didAdd shuqi's iPhone
    /// TRACE didOpenSession attempt=0 err=-9943 "Please unlock"
    ///    ...and nothing further, ever
    /// ```
    ///
    /// The device **is** advertised, and `didOpenSessionWithError` fires **exactly once**.
    /// The gateway then re-requests and the framework never calls back again, so the retry
    /// counter never advanced and the retry-exhausted branch was unreachable. Counting
    /// callbacks that never arrive cannot work; only a deadline can end this wait.
    ///
    /// The scan gives up and lets the user retry, which is what `RecoveryBanner` exists for.
    func testTheDiscoveryDeadlineEndsTheWaitWithoutCuttingOffARescan() {
        // A rescan was measured at 9.8 s: the previous helper must exit and release the
        // device before a new process is offered it. A 5 s deadline was tried first and
        // broke every rescan, so this needs real headroom above that.
        XCTAssertGreaterThan(
            DeviceDiscoveryPolicy.deadline,
            .seconds(15),
            "A rescan takes about 10 s; anything tighter fails healthy devices."
        )
        XCTAssertLessThan(
            DeviceDiscoveryPolicy.deadline,
            .seconds(60),
            "It still has to end the wait long before the old 180 s hang."
        )
    }

    /// The deadline covers only "no session yet", never enumeration, so catalog size is
    /// irrelevant to it. The ceiling is the one that bounds the whole scan, and it scales.
    func testTheScanCeilingScalesWithCatalogSize() {
        let small = DeviceDiscoveryPolicy.scanCeiling(previousFileCount: 4_000)
        let large = DeviceDiscoveryPolicy.scanCeiling(previousFileCount: 60_000)

        XCTAssertGreaterThan(large, small, "A larger library must get more time, not less.")
        XCTAssertGreaterThan(
            large,
            .seconds(300),
            "60,000 files must not be cut off by a cap chosen for 4,000."
        )
    }

    /// A first scan has no history, so it falls back to a floor generous enough for a
    /// typical library plus the helper handover.
    func testAFirstScanUsesAGenerousFloor() {
        let first = DeviceDiscoveryPolicy.scanCeiling(previousFileCount: nil)
        XCTAssertGreaterThanOrEqual(first, .seconds(40))
        XCTAssertEqual(first, DeviceDiscoveryPolicy.scanCeiling)
    }

    /// The floor still applies to a tiny catalog: a nearly empty phone must not get a
    /// ceiling so small that the helper handover alone exceeds it.
    func testATinyCatalogStillGetsTheFloor() {
        XCTAssertEqual(
            DeviceDiscoveryPolicy.scanCeiling(previousFileCount: 5),
            DeviceDiscoveryPolicy.scanCeiling(previousFileCount: nil)
        )
    }

    /// The ceiling must stay far above the measured cost, so it only ever catches a scan
    /// that is not going to finish. ~3,960 files enumerate in about 1.1 s.
    func testTheCeilingIsOrdersOfMagnitudeAboveTheMeasuredCost() {
        let ceiling = DeviceDiscoveryPolicy.scanCeiling(previousFileCount: 3_960)
        XCTAssertGreaterThan(
            ceiling,
            .seconds(30),
            "A scan measured at ~1.1 s must never be cut off by this."
        )
    }
}
