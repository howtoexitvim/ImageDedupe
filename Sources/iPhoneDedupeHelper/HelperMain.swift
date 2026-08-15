import DeduperCore
import DeviceMediaKit
import Foundation

/// A short-lived process that owns one ImageCaptureCore client and serves one catalog
/// generation over stdin/stdout.
///
/// This exists for one reason: `deviceDidBecomeReady(withCompleteContentCatalog:)` is
/// delivered once per `ICCameraDevice` object. A process that already holds a device can
/// never enumerate it again — a reopened session reports `hasOpenSession=true` with
/// `mediaFiles` permanently empty, and the framework does not re-advertise a device this
/// process holds. A fresh process is therefore the only way to observe the device as it is
/// now, which was measured directly: an in-process rescan missed a photo taken seconds
/// earlier, while a new process saw it immediately.
///
/// The helper owns the whole device layer, not just scanning. Tokens resolve to live
/// `ICCameraFile` objects held in this process's memory, so download and delete must run
/// here too; handing a token to another process would resolve nothing.
@main
enum HelperMain {
    static func main() {
        // Buffered stdout would hold responses until the pipe filled, which reads to the
        // app as a hang, so every response is written and flushed immediately.
        setvbuf(stdout, nil, _IONBF, 0)

        // ImageCaptureCore delivers every callback through the main thread's run loop, so
        // the process must actually run one. An `async` `main()` returns to the concurrency
        // runtime instead, and the device callbacks then never arrive — the scan sat until
        // its full timeout even though the device was present and idle. Starting the work
        // as a task and running the run loop until it finishes is what the framework needs.
        Task { @MainActor in
            let runner = HelperRunner()
            await runner.run()
            exit(0)
        }
        RunLoop.main.run()
    }
}

@MainActor
final class HelperRunner {
    private let gateway = ImageCaptureDeviceGateway()
    private let stagingManager = ImportStagingManager.applicationCaches()
    private let output = FileHandle.standardOutput

    /// Cancels whatever operation is currently in flight.
    ///
    /// Requests are read on a background thread so a `cancel` arriving mid-download is
    /// acted on immediately rather than after the operation it is meant to interrupt.
    private var activeCancellation: DeviceOperationCancellation?

    /// The operation currently running, so `shutdown` and a closed stdin can wait for it
    /// and so operations stay serialized with one another.
    private var activeOperation: Task<Void, Never>?

    func run() async {
        send(.ready(version: HelperProtocol.version), id: HelperProtocol.greetingID)

        for await envelope in Self.requests() {
            let request = envelope.payload
            switch request {
            case .shutdown:
                // Wait for work already in flight instead of exiting underneath it.
                // Requests arrive as fast as the app can write them, so a scan followed
                // immediately by `shutdown` is normal, and returning here would kill the
                // scan and send nothing back.
                await activeOperation?.value
                return
            case .cancel:
                // Cancel must never queue behind the operation it is meant to interrupt,
                // so it is handled here without awaiting anything.
                activeCancellation?.cancel()
            default:
                // Operations run outside this loop so the loop stays free to receive a
                // `cancel` while one is in flight. They remain serialized with each other
                // by the gateway's own non-reentrant scheduler and by awaiting the previous
                // operation below, so this never issues concurrent ImageCaptureCore
                // requests; it only keeps the reader responsive. Awaiting inline instead is
                // what would make Cancel dead.
                let previous = activeOperation
                activeOperation = Task { @MainActor [weak self] in
                    await previous?.value
                    await self?.handle(request, id: envelope.id)
                }
            }
        }

        // stdin closed. Finish what is running so a half-completed device command is not
        // abandoned mid-flight.
        await activeOperation?.value
    }

    private func handle(_ request: HelperRequest, id: UUID) async {
        let cancellation = DeviceOperationCancellation()
        activeCancellation = cancellation
        defer { activeCancellation = nil }

        do {
            switch request {
            case .scan(let timeout):
                let snapshot = try await gateway.scan(timeout: .seconds(timeout))
                send(.scanned(snapshot: snapshot), id: id)

            case .thumbnail(let token, let maxPixelSize, let timeout):
                let data = try await gateway.thumbnailData(
                    for: token,
                    maxPixelSize: maxPixelSize,
                    timeout: .seconds(timeout)
                )
                send(.thumbnail(data: data), id: id)

            case .metadata(let token, let timeout):
                let summary = try await gateway.metadata(for: token, timeout: .seconds(timeout))
                send(.metadata(summary: summary), id: id)

            case .download(let tokens, let destination, let timeout):
                try await download(
                    tokens,
                    to: destination,
                    timeout: timeout,
                    cancellation: cancellation,
                    id: id
                )

            case .delete(let tokens, let confirmed, let timeout):
                // The confirmation flag is re-checked by the gateway itself; passing it
                // through rather than defaulting it keeps the helper from being a place
                // where an unconfirmed delete could become a confirmed one.
                let summary = try await gateway.delete(
                    tokens,
                    confirmed: confirmed,
                    cancellation: cancellation,
                    onProgress: { [weak self] progress in
                        self?.send(.progress(
                            completed: progress.completedItems,
                            total: progress.totalItems,
                            filename: progress.currentFilename
                        ), id: id)
                    },
                    timeout: .seconds(timeout)
                )
                send(.deleted(
                    summary: summary,
                    observedRemovedHandles: gateway.observedRemovals
                ), id: id)

            case .cancel, .shutdown:
                break
            }
        } catch {
            send(.failed(
                message: "\(error)",
                isCancellation: Self.isCancellation(error)
            ), id: id)
        }
    }

    /// Downloads into the staging directory the app nominated, and stops there.
    ///
    /// The helper deliberately does **not** commit to the user's destination. Committing
    /// stays in the app, which owns the destination preflight, the imported-path policy,
    /// and the identity checks that make a partial download unable to appear as a finished
    /// file. Moving that here would duplicate the security surface in a second process.
    private func download(
        _ tokens: [DeviceFileToken],
        to stagingDirectory: URL,
        timeout: Double,
        cancellation: DeviceOperationCancellation,
        id: UUID
    ) async throws {
        let session = try stagingManager.adoptSession(at: stagingDirectory)
        let summary = await gateway.download(
            tokens,
            to: session,
            cancellation: cancellation,
            onProgress: { [weak self] progress in
                self?.send(.progress(
                    completed: progress.completedItems,
                    total: progress.totalItems,
                    filename: progress.currentFilename
                ), id: id)
            },
            timeout: .seconds(timeout)
        )
        send(.downloaded(summary: summary), id: id)
    }

    private func send(_ response: HelperResponse, id: UUID) {
        guard let data = try? HelperCodec.encode(
            HelperResponseEnvelope(id: id, payload: response)
        ) else { return }
        output.write(data)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if let gatewayError = error as? DeviceGatewayError, case .canceled = gatewayError {
            return true
        }
        return error is CancellationError
    }

    /// Reads requests off stdin on a background thread.
    ///
    /// Reading must not block the main actor: the gateway's callbacks are delivered there,
    /// so a blocking read would deadlock the very operation whose progress it is waiting to
    /// report — and would make `cancel` unreachable while a download was running.
    private static func requests() -> AsyncStream<HelperRequestEnvelope> {
        AsyncStream { continuation in
            let thread = Thread {
                var buffer = Data()
                let input = FileHandle.standardInput
                while true {
                    let chunk = input.availableData
                    if chunk.isEmpty {
                        // The app closed the pipe, or exited. Either way this helper's
                        // catalog is now unreachable and the process should end.
                        continuation.finish()
                        return
                    }
                    buffer.append(chunk)
                    for line in HelperCodec.lines(from: &buffer) {
                        guard let envelope = try? HelperCodec.decode(
                            HelperRequestEnvelope.self,
                            from: line
                        ) else { continue }
                        continuation.yield(envelope)
                        if case .shutdown = envelope.payload {
                            continuation.finish()
                            return
                        }
                    }
                }
            }
            thread.stackSize = 512 * 1_024
            thread.start()
        }
    }
}
