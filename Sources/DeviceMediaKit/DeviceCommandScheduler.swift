import Foundation

public actor DeviceCommandScheduler {
    public enum Priority: Sendable {
        case high
        case low
    }

    public enum AcquireError: Error, Equatable, LocalizedError, Sendable {
        case generationCanceled
        case invalidated
        case cancelling

        public var errorDescription: String? {
            switch self {
            case .generationCanceled:
                "This request belongs to an older device scan."
            case .invalidated:
                "The device gateway stopped after an unacknowledged operation. Reopen the app before retrying."
            case .cancelling:
                "The previous device operation is still being canceled. Try again in a moment."
            }
        }
    }

    public struct Lease: Equatable, Sendable {
        fileprivate let id: UUID
        let priority: Priority
        let generation: UUID?

        fileprivate init(priority: Priority, generation: UUID?) {
            self.id = UUID()
            self.priority = priority
            self.generation = generation
        }
    }

    private struct Waiter {
        let lease: Lease
        let continuation: CheckedContinuation<Result<Lease, AcquireError>, Never>
    }

    private var highPriorityWaiters: [Waiter] = []
    private var lowPriorityWaiters: [Waiter] = []
    private var canceledGenerations: Set<UUID> = []

    /// Permanent latch. Set only when a framework operation was never acknowledged, so the
    /// device may still be mid-command and no further submission is safe.
    private var isInvalidated = false

    /// Temporary hold while a cancellation settles.
    ///
    /// A user-initiated Cancel is not the same as an unacknowledged operation. Latching the
    /// gateway for an acknowledged cancel is what made one Download Cancel or Delete Cancel
    /// permanently break downloads, previews, delete, and rescan until relaunch.
    private var isCancelling = false

    private(set) var activeLease: Lease?

    var waitingCount: Int {
        highPriorityWaiters.count + lowPriorityWaiters.count
    }

    public init() {}

    public func acquire(priority: Priority, generation: UUID?) async throws -> Lease {
        if isInvalidated {
            throw AcquireError.invalidated
        }
        if isCancelling {
            throw AcquireError.cancelling
        }
        if let generation, canceledGenerations.contains(generation) {
            throw AcquireError.generationCanceled
        }

        let lease = Lease(priority: priority, generation: generation)
        if activeLease == nil, highPriorityWaiters.isEmpty, lowPriorityWaiters.isEmpty {
            activeLease = lease
            return lease
        }

        let result = await withCheckedContinuation { continuation in
            let waiter = Waiter(lease: lease, continuation: continuation)
            switch priority {
            case .high:
                highPriorityWaiters.append(waiter)
            case .low:
                lowPriorityWaiters.append(waiter)
            }
        }
        return try result.get()
    }

    public func release(_ lease: Lease) {
        guard activeLease == lease else {
            return
        }

        activeLease = nil
        startNextCommand()
    }

    public func cancelQueued(generation: UUID) {
        canceledGenerations.insert(generation)
        rejectWaiters(in: &highPriorityWaiters, generation: generation)
        rejectWaiters(in: &lowPriorityWaiters, generation: generation)
    }

    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        rejectAllWaiters(in: &highPriorityWaiters)
        rejectAllWaiters(in: &lowPriorityWaiters)
    }

    /// Holds new submissions while a timed-out read is torn down.
    ///
    /// Scan, thumbnail, and metadata issue no mutating command, so an unfinished one leaves
    /// nothing uncertain on the device and must stay retryable. Latching here is what made a
    /// timed-out post-delete verification scan poison every following retry with
    /// `invalidated`, so the delete could never be verified without relaunching.
    public func suspendForReadTimeout() {
        suspendForCancellation()
    }

    /// Holds new submissions while a user-initiated cancellation settles.
    ///
    /// Queued work is rejected so nothing is submitted on top of a command being torn down,
    /// but unlike `invalidate()` this is reversible.
    public func suspendForCancellation() {
        guard !isCancelling else { return }
        isCancelling = true
        rejectAllWaiters(in: &highPriorityWaiters, with: .cancelling)
        rejectAllWaiters(in: &lowPriorityWaiters, with: .cancelling)
    }

    /// Releases the hold once the framework acknowledged the cancellation.
    ///
    /// Deliberately cannot clear `isInvalidated`: if the operation went unacknowledged, the
    /// device state is genuinely uncertain and the permanent latch must survive.
    public func resumeAfterAcknowledgedCancellation() {
        isCancelling = false
        startNextCommand()
    }

    private func startNextCommand() {
        guard activeLease == nil, !isInvalidated, !isCancelling else {
            return
        }

        while let waiter = popNextWaiter() {
            if let generation = waiter.lease.generation,
               canceledGenerations.contains(generation) {
                waiter.continuation.resume(returning: .failure(.generationCanceled))
                continue
            }

            activeLease = waiter.lease
            waiter.continuation.resume(returning: .success(waiter.lease))
            return
        }
    }

    private func popNextWaiter() -> Waiter? {
        if !highPriorityWaiters.isEmpty {
            return highPriorityWaiters.removeFirst()
        }
        if !lowPriorityWaiters.isEmpty {
            return lowPriorityWaiters.removeFirst()
        }
        return nil
    }

    private func rejectWaiters(in waiters: inout [Waiter], generation: UUID) {
        var retained: [Waiter] = []
        retained.reserveCapacity(waiters.count)

        for waiter in waiters {
            if waiter.lease.generation == generation {
                waiter.continuation.resume(returning: .failure(.generationCanceled))
            } else {
                retained.append(waiter)
            }
        }
        waiters = retained
    }

    private func rejectAllWaiters(
        in waiters: inout [Waiter],
        with error: AcquireError = .invalidated
    ) {
        for waiter in waiters {
            waiter.continuation.resume(returning: .failure(error))
        }
        waiters.removeAll()
    }
}
