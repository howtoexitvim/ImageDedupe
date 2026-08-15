import XCTest
@testable import DeviceMediaKit

@MainActor
final class DeviceCommandSchedulerTests: XCTestCase {
    func testSchedulerDoesNotStartSecondCommandUntilActiveLeaseIsReleased() async throws {
        let scheduler = DeviceCommandScheduler()
        let first = try await scheduler.acquire(priority: .low, generation: nil)

        let secondTask = Task {
            try await scheduler.acquire(priority: .low, generation: nil)
        }
        await waitUntil { await scheduler.waitingCount == 1 }

        let activeBeforeRelease = await scheduler.activeLease
        XCTAssertEqual(activeBeforeRelease, first)
        await scheduler.release(first)

        let second = try await secondTask.value
        let activeAfterRelease = await scheduler.activeLease
        XCTAssertEqual(activeAfterRelease, second)
        await scheduler.release(second)
    }

    func testSchedulerStartsQueuedHighPriorityCommandBeforeLowPriorityCommand() async throws {
        let scheduler = DeviceCommandScheduler()
        let first = try await scheduler.acquire(priority: .low, generation: nil)
        let lowGeneration = UUID()
        let highGeneration = UUID()

        let lowTask = Task {
            try await scheduler.acquire(priority: .low, generation: lowGeneration)
        }
        await waitUntil { await scheduler.waitingCount == 1 }

        let highTask = Task {
            try await scheduler.acquire(priority: .high, generation: highGeneration)
        }
        await waitUntil { await scheduler.waitingCount == 2 }

        await scheduler.release(first)
        await waitUntil { await scheduler.activeLease?.generation == highGeneration }

        let high = try await highTask.value
        XCTAssertEqual(high.priority, .high)
        await scheduler.release(high)

        let low = try await lowTask.value
        XCTAssertEqual(low.generation, lowGeneration)
        await scheduler.release(low)
    }

    func testSchedulerPreservesFIFOOrderWithinPriority() async throws {
        let scheduler = DeviceCommandScheduler()
        let active = try await scheduler.acquire(priority: .high, generation: nil)
        let firstGeneration = UUID()
        let secondGeneration = UUID()

        let firstTask = Task {
            try await scheduler.acquire(priority: .low, generation: firstGeneration)
        }
        await waitUntil { await scheduler.waitingCount == 1 }

        let secondTask = Task {
            try await scheduler.acquire(priority: .low, generation: secondGeneration)
        }
        await waitUntil { await scheduler.waitingCount == 2 }

        await scheduler.release(active)
        await waitUntil { await scheduler.activeLease?.generation == firstGeneration }

        let first = try await firstTask.value
        await scheduler.release(first)
        let second = try await secondTask.value
        XCTAssertEqual(second.generation, secondGeneration)
        await scheduler.release(second)
    }

    func testCancelGenerationRejectsQueuedAndFutureCommandsWithoutInterruptingActiveCommand() async throws {
        let scheduler = DeviceCommandScheduler()
        let activeGeneration = UUID()
        let canceledGeneration = UUID()
        let active = try await scheduler.acquire(priority: .high, generation: activeGeneration)

        let queuedTask = Task {
            try await scheduler.acquire(priority: .low, generation: canceledGeneration)
        }
        await waitUntil { await scheduler.waitingCount == 1 }

        await scheduler.cancelQueued(generation: canceledGeneration)

        do {
            _ = try await queuedTask.value
            XCTFail("Expected the queued command to be canceled")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .generationCanceled)
        }
        let activeAfterCancellation = await scheduler.activeLease
        XCTAssertEqual(activeAfterCancellation, active)

        do {
            _ = try await scheduler.acquire(priority: .low, generation: canceledGeneration)
            XCTFail("Expected future commands from the canceled generation to be rejected")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .generationCanceled)
        }

        await scheduler.release(active)
    }

    func testLateOrDuplicateReleaseCannotReleaseAnotherCommand() async throws {
        let scheduler = DeviceCommandScheduler()
        let first = try await scheduler.acquire(priority: .high, generation: nil)
        await scheduler.release(first)

        let second = try await scheduler.acquire(priority: .high, generation: nil)
        let thirdTask = Task {
            try await scheduler.acquire(priority: .high, generation: nil)
        }
        await waitUntil { await scheduler.waitingCount == 1 }

        await scheduler.release(first)
        let activeAfterLateRelease = await scheduler.activeLease
        let waitingAfterLateRelease = await scheduler.waitingCount
        XCTAssertEqual(activeAfterLateRelease, second)
        XCTAssertEqual(waitingAfterLateRelease, 1)

        await scheduler.release(second)
        let third = try await thirdTask.value
        let activeAfterSecondRelease = await scheduler.activeLease
        XCTAssertEqual(activeAfterSecondRelease, third)
        await scheduler.release(third)
    }

    func testInvalidationRejectsQueuedAndFutureCommandsEvenAfterActiveRelease() async throws {
        let scheduler = DeviceCommandScheduler()
        let active = try await scheduler.acquire(priority: .low, generation: nil)
        let queuedTask = Task { try await scheduler.acquire(priority: .high, generation: nil) }
        await waitUntil { await scheduler.waitingCount == 1 }

        await scheduler.invalidate()

        do {
            _ = try await queuedTask.value
            XCTFail("Expected queued command rejection")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .invalidated)
        }
        await scheduler.release(active)
        do {
            _ = try await scheduler.acquire(priority: .high, generation: nil)
            XCTFail("Expected future command rejection")
        } catch {
            XCTAssertEqual(error as? DeviceCommandScheduler.AcquireError, .invalidated)
        }
    }

    func testDeviceFileTokenRoundTripsAndFingerprintNormalizationIsStable() throws {
        let generation = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_786_780_800)
        let token = DeviceFileToken(
            generation: generation,
            objectHandle: 42,
            fingerprint: DeviceFileFingerprint(
                name: "  IMG_É001.HeIc  ",
                kind: " heic ",
                size: 123_456,
                timestamp: timestamp
            )
        )

        XCTAssertEqual(token.fingerprint.name, "img_é001.heic")
        XCTAssertEqual(token.fingerprint.kind, "HEIC")

        let encoded = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(DeviceFileToken.self, from: encoded)
        XCTAssertEqual(decoded, token)
    }

    private func waitUntil(
        attempts: Int = 1_000,
        condition: @escaping @Sendable () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<attempts {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}
