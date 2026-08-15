import Foundation

/// Main-actor cancellation shared by the UI and the ImageCapture gateway.
@MainActor
public final class DeviceOperationCancellation {
    private var requested = false
    private var activeProgress: Progress?
    private var activeCancelAction: (() -> Void)?

    public init() {}

    public var isCancellationRequested: Bool {
        requested
    }

    /// Returns `true` only for the first request.
    @discardableResult
    public func cancel() -> Bool {
        guard !requested else {
            return false
        }
        requested = true
        activeProgress?.cancel()
        activeCancelAction?()
        return true
    }

    public func bind(_ progress: Progress?, onCancel: (() -> Void)? = nil) {
        activeProgress = progress
        activeCancelAction = onCancel
        if requested {
            progress?.cancel()
            onCancel?()
        }
    }

    public func unbind(_ progress: Progress?) {
        if progress == nil || activeProgress === progress {
            activeProgress = nil
            activeCancelAction = nil
        }
    }
}
