import DeviceMediaKit
import Foundation
import XCTest

/// `DeviceOperationCancellation.cancel()` runs Foundation/ImageCaptureCore cancellation
/// synchronously. If the framework never delivers a completion afterwards, the awaiting
/// continuation must still settle rather than leaving the UI at `Canceling…` forever.
@MainActor
final class DeviceCancellationBoundaryTests: XCTestCase {
    func testCancelBoundedWaitSettlesWhenTheFrameworkNeverCallsBack() async {
        let cancellation = DeviceOperationCancellation()
        var settled = false

        let task = Task { @MainActor in
            _ = await cancellation.awaitFrameworkAcknowledgement(
                within: .milliseconds(50),
                // Models ImageCaptureCore accepting the cancel and then going silent.
                acknowledge: { _ in }
            )
            settled = true
        }

        _ = cancellation.cancel()
        _ = await task.value

        XCTAssertTrue(settled, "A silent framework must not block the cancellation path.")
    }

    func testCancelReportsPromptAcknowledgementWhenTheFrameworkDoesRespond() async {
        let cancellation = DeviceOperationCancellation()

        let task = Task { @MainActor in
            await cancellation.awaitFrameworkAcknowledgement(
                within: .seconds(5),
                acknowledge: { finish in finish() }
            )
        }
        _ = cancellation.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome, .acknowledged)
    }

    func testSilentFrameworkIsReportedAsUnacknowledgedRatherThanAsSuccess() async {
        let cancellation = DeviceOperationCancellation()

        let task = Task { @MainActor in
            await cancellation.awaitFrameworkAcknowledgement(
                within: .milliseconds(50),
                acknowledge: { _ in }
            )
        }
        _ = cancellation.cancel()
        let outcome = await task.value

        XCTAssertEqual(
            outcome,
            .unacknowledged,
            "A silent framework must be reported honestly, never faked as acknowledged."
        )
    }

    func testAcknowledgementArrivingAfterTheBoundIsIgnored() async {
        let cancellation = DeviceOperationCancellation()
        var lateFinish: (() -> Void)?

        let task = Task { @MainActor in
            await cancellation.awaitFrameworkAcknowledgement(
                within: .milliseconds(50),
                acknowledge: { finish in lateFinish = finish }
            )
        }
        _ = cancellation.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .unacknowledged)

        // The framework finally responds; this must not trap or resume a second time.
        lateFinish?()
        lateFinish?()
    }
}
