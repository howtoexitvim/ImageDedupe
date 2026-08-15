import Foundation

public enum DeviceCallbackError: Error, Equatable, Sendable {
    case timedOut
    case canceled
    case failed(String)
}

@MainActor
final class DeviceOneShotCallback<Value: Sendable> {
    private var activeToken: UUID?
    private var continuation: CheckedContinuation<Result<Value, DeviceCallbackError>, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var terminalOverride: DeviceCallbackError?

    var isPending: Bool {
        continuation != nil
    }

    func wait(
        timeout: Duration,
        onTimeout: @escaping @MainActor @Sendable () async -> Void = {},
        onCancel: @escaping @MainActor @Sendable () async -> Void = {},
        start: (UUID) -> Void
    ) async throws -> Value {
        precondition(continuation == nil, "A one-shot callback cannot be reused while pending")
        let token = UUID()

        return try await withTaskCancellationHandler {
            let result = await withCheckedContinuation { continuation in
                self.activeToken = token
                self.continuation = continuation
                self.timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.requestTerminal(
                        token: token,
                        error: .timedOut,
                        action: onTimeout
                    )
                }
                start(token)
            }
            return try result.get()
        } onCancel: {
            Task { @MainActor [weak self] in
                await self?.requestTerminal(
                    token: token,
                    error: .canceled,
                    action: onCancel
                )
            }
        }
    }

    private func requestTerminal(
        token: UUID,
        error: DeviceCallbackError,
        action: @MainActor @Sendable () async -> Void
    ) async {
        guard token == activeToken, continuation != nil, terminalOverride == nil else { return }
        terminalOverride = error
        await action()
        complete(token: token, result: .failure(error))
    }

    func complete(token: UUID, result: Result<Value, DeviceCallbackError>) {
        guard token == activeToken, let continuation else {
            return
        }

        self.continuation = nil
        activeToken = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        let finalResult = terminalOverride.map { Result<Value, DeviceCallbackError>.failure($0) } ?? result
        terminalOverride = nil
        continuation.resume(returning: finalResult)
    }
}
