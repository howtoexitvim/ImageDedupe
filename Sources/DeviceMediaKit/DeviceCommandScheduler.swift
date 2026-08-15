import Foundation

public actor DeviceCommandScheduler {
    public enum Priority: Sendable {
        case high
        case low
    }

    public enum AcquireError: Error, Equatable, LocalizedError, Sendable {
        case generationCanceled
        case invalidated

        public var errorDescription: String? {
            switch self {
            case .generationCanceled:
                "This request belongs to an older device scan."
            case .invalidated:
                "The device gateway stopped after an unacknowledged operation. Reopen the app before retrying."
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
    private var isInvalidated = false

    private(set) var activeLease: Lease?

    var waitingCount: Int {
        highPriorityWaiters.count + lowPriorityWaiters.count
    }

    public init() {}

    public func acquire(priority: Priority, generation: UUID?) async throws -> Lease {
        if isInvalidated {
            throw AcquireError.invalidated
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

    private func startNextCommand() {
        guard activeLease == nil else {
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

    private func rejectAllWaiters(in waiters: inout [Waiter]) {
        for waiter in waiters {
            waiter.continuation.resume(returning: .failure(.invalidated))
        }
        waiters.removeAll()
    }
}
