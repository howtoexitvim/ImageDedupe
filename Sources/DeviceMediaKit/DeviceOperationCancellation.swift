import Foundation

/// Thread-safe cancellation shared by the AppKit main actor and synchronous
/// ImageCaptureCore controller loops.
public final class DeviceOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    private var activeProgress: Progress?

    public init() {}

    public var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    /// Returns `true` only for the first request.
    @discardableResult
    public func cancel() -> Bool {
        let progress: Progress?
        lock.lock()
        guard !requested else {
            lock.unlock()
            return false
        }
        requested = true
        progress = activeProgress
        lock.unlock()

        progress?.cancel()
        return true
    }

    public func bind(_ progress: Progress?) {
        let shouldCancel: Bool
        lock.lock()
        activeProgress = progress
        shouldCancel = requested
        lock.unlock()

        if shouldCancel {
            progress?.cancel()
        }
    }

    public func unbind(_ progress: Progress?) {
        lock.lock()
        if activeProgress === progress {
            activeProgress = nil
        }
        lock.unlock()
    }
}
