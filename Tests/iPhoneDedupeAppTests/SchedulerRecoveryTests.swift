import XCTest
@testable import DeviceMediaKit

/// A user-initiated Cancel used to brick the gateway.
///
/// Every cancel path called `scheduler.invalidate()`, which latched `isInvalidated` with no
/// reset anywhere in the source. After one Download Cancel or Delete Cancel, every later
/// command — download, thumbnail/preview, delete, and even a fresh scan — failed with
/// `The device gateway stopped after an unacknowledged operation.` until the app relaunched.
///
/// A cancel the framework acknowledges leaves the device in a known-good state and must
/// recover. Only a genuinely *unacknowledged* operation may latch the gateway.
@MainActor
final class SchedulerRecoveryTests: XCTestCase {
    func testAcknowledgedCancellationDoesNotPermanentlyStopTheGateway() async throws {
        let scheduler = DeviceCommandScheduler()

        // The user cancels, and the framework confirms the command is finished.
        await scheduler.suspendForCancellation()
        await scheduler.resumeAfterAcknowledgedCancellation()

        let lease = try await scheduler.acquire(priority: .high, generation: nil)
        await scheduler.release(lease)
    }

    func testUnacknowledgedOperationStillLatchesTheGateway() async {
        let scheduler = DeviceCommandScheduler()

        await scheduler.invalidate()

        do {
            _ = try await scheduler.acquire(priority: .high, generation: nil)
            XCTFail("An unacknowledged operation must still block later commands.")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .invalidated)
        }
    }

    func testSuspensionRejectsCommandsUntilTheCancellationSettles() async {
        let scheduler = DeviceCommandScheduler()
        await scheduler.suspendForCancellation()

        do {
            _ = try await scheduler.acquire(priority: .high, generation: nil)
            XCTFail("While a cancellation is settling, new commands must not be admitted.")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .cancelling)
        }
    }

    func testResumeAfterAnUnacknowledgedCancellationLeavesTheGatewayLatched() async {
        let scheduler = DeviceCommandScheduler()
        await scheduler.suspendForCancellation()

        // The framework never acknowledged, so the device may still be mid-command.
        await scheduler.invalidate()
        await scheduler.resumeAfterAcknowledgedCancellation()

        do {
            _ = try await scheduler.acquire(priority: .high, generation: nil)
            XCTFail("Resume must not clear a latch set by an unacknowledged operation.")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .invalidated)
        }
    }

    func testAFreshScanRecoversTheGatewayAfterAnAcknowledgedCancellation() async throws {
        let scheduler = DeviceCommandScheduler()
        await scheduler.suspendForCancellation()
        await scheduler.resumeAfterAcknowledgedCancellation()

        // A rescan is the user's recovery path and must be admitted.
        let scanLease = try await scheduler.acquire(priority: .high, generation: nil)
        await scheduler.release(scanLease)

        // Previews and downloads work again afterwards.
        let previewLease = try await scheduler.acquire(priority: .low, generation: UUID())
        await scheduler.release(previewLease)
    }
}
