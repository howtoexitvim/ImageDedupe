import Foundation

/// Builds ImageCaptureCore callbacks outside the gateway's `@MainActor` context,
/// then transfers only a Sendable value to the main actor.
enum DeviceFrameworkCallbackBridge {
    nonisolated static func ignore<Input>() -> @Sendable (Input) -> Void {
        { _ in }
    }

    nonisolated static func hop<Input1, Input2, Output: Sendable>(
        transform: @escaping @Sendable (Input1, Input2) -> Output,
        deliver: @escaping @MainActor @Sendable (Output) -> Void
    ) -> @Sendable (Input1, Input2) -> Void {
        { input1, input2 in
            let output = transform(input1, input2)
            Task { @MainActor in
                deliver(output)
            }
        }
    }
}
