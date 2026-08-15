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

    /// Outcome of waiting for the framework to acknowledge a cancellation.
    ///
    /// Reported honestly: `unacknowledged` means ImageCaptureCore never answered, so the
    /// affected item is uncertain. It must never be presented as a canceled-and-clean or
    /// successful result.
    public enum AcknowledgementOutcome: Equatable, Sendable {
        case acknowledged
        case unacknowledged
    }

    /// Waits at most `bound` for the framework to acknowledge cancellation.
    ///
    /// `cancel()` invokes Foundation/ImageCaptureCore cancellation synchronously, before the
    /// awaiting continuation is completed. If the framework then goes silent, nothing else
    /// resumes that continuation, which is how a Delete Cancel could sit at
    /// `Canceling delete…` indefinitely. This wait always settles: `acknowledge` receives a
    /// `finish` handle it may call at most usefully once, and any later call is ignored.
    public func awaitFrameworkAcknowledgement(
        within bound: Duration,
        acknowledge: @MainActor (@escaping @MainActor () -> Void) -> Void
    ) async -> AcknowledgementOutcome {
        var hasSettled = false
        let outcome: AcknowledgementOutcome = await withCheckedContinuation { continuation in
            let settle: @MainActor (AcknowledgementOutcome) -> Void = { result in
                guard !hasSettled else { return }
                hasSettled = true
                continuation.resume(returning: result)
            }
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: bound)
                settle(.unacknowledged)
            }
            acknowledge {
                timeoutTask.cancel()
                settle(.acknowledged)
            }
        }
        return outcome
    }
}
