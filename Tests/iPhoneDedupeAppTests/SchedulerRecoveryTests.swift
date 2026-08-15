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

    /// A timed-out *read* must stay retryable.
    ///
    /// Observed on a real device: a post-delete verification scan timed out, which latched
    /// the gateway, so the verifier's own retry loop then failed with `invalidated` and the
    /// delete could never be verified in that process. A scan issues no mutating command,
    /// so an unfinished one leaves nothing uncertain on the device.
    func testTimedOutReadStaysRetryableInsteadOfLatchingTheGateway() async throws {
        let scheduler = DeviceCommandScheduler()

        await scheduler.suspendForReadTimeout()
        await scheduler.resumeAfterAcknowledgedCancellation()

        let retry = try await scheduler.acquire(priority: .high, generation: nil)
        await scheduler.release(retry)
    }

    func testTimedOutMutatingCommandStillLatchesTheGateway() async {
        let scheduler = DeviceCommandScheduler()

        // A delete that never came back may still be executing on the device.
        await scheduler.invalidate()

        do {
            _ = try await scheduler.acquire(priority: .high, generation: nil)
            XCTFail("An unacknowledged mutating command must still block later commands.")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .invalidated)
        }
    }

    /// The second one-way latch.
    ///
    /// `canceledGenerations` was only ever inserted into, so once a generation was canceled
    /// every later request carrying it failed with `This request belongs to an older device
    /// scan.` The current catalog's generation is exactly what Download, preview, and Delete
    /// pass, so one canceled Download poisoned all of them until a rescan.
    func testCancelingAGenerationDoesNotPoisonTheCurrentCatalogForever() async throws {
        let scheduler = DeviceCommandScheduler()
        let generation = UUID()

        await scheduler.cancelQueued(generation: generation)
        do {
            _ = try await scheduler.acquire(priority: .low, generation: generation)
            XCTFail("Queued work from the canceled generation must be rejected.")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .generationCanceled)
        }

        // The catalog is still valid, so the user retrying must be admitted again.
        await scheduler.reinstate(generation: generation)
        let lease = try await scheduler.acquire(priority: .low, generation: generation)
        await scheduler.release(lease)
    }

    func testCanceledGenerationSetDoesNotGrowWithoutBound() async throws {
        let scheduler = DeviceCommandScheduler()
        var generations: [UUID] = []

        for _ in 0..<50 {
            let generation = UUID()
            generations.append(generation)
            await scheduler.cancelQueued(generation: generation)
        }

        // Only the most recent supersessions need to be remembered; retaining every
        // generation for the life of the process is a leak as well as a correctness trap.
        let retained = await scheduler.canceledGenerationCount
        XCTAssertLessThanOrEqual(retained, 8, "Canceled generations must be bounded.")

        // The oldest ones are forgotten, so their requests are no longer rejected outright.
        let oldest = try XCTUnwrap(generations.first)
        let lease = try await scheduler.acquire(priority: .low, generation: oldest)
        await scheduler.release(lease)
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
