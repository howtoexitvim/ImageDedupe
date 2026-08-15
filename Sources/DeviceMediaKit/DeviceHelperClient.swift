import DeduperCore
import Foundation

public enum DeviceHelperError: Error, LocalizedError, Equatable {
    case helperNotFound(String)
    case helperExited(String)
    case versionMismatch(expected: Int, actual: Int)
    case unexpectedResponse
    case failed(String)
    case canceled

    public var errorDescription: String? {
        switch self {
        case .helperNotFound(let path):
            return "The device helper is missing from the app bundle (\(path))."
        case .helperExited(let detail):
            return "The device helper stopped unexpectedly. \(detail)"
        case .versionMismatch(let expected, let actual):
            return "The device helper speaks protocol \(actual), but this app expects \(expected). Rebuild the app bundle."
        case .unexpectedResponse:
            return "The device helper sent an unexpected response."
        case .failed(let message):
            return message
        case .canceled:
            return "The operation was canceled."
        }
    }
}

/// Drives one device helper process.
///
/// One client owns exactly one helper, and one helper serves exactly one catalog
/// generation. Rescanning means retiring this client and starting another, because
/// ImageCaptureCore will not enumerate a device twice within a single process.
///
/// Requests are serialized here as well as in the helper's own scheduler. The helper is the
/// authority on device ordering; this queue exists so that a caller cannot interleave two
/// requests on one pipe and mis-attribute the replies.
public actor DeviceHelperClient {
    private let executableURL: URL
    private var process: Process?
    private var input: FileHandle?
    /// One mailbox per in-flight request, keyed by the id its replies carry.
    ///
    /// The app issues many requests at once on this one pipe. Before correlation existed,
    /// each waiter took the next response to arrive, so a thumbnail could consume a
    /// download's reply and a tile could be handed another tile's image.
    private var mailboxes: [UUID: Mailbox] = [:]
    private var isStreamFinished = false

    /// Buffered replies for one request, and whoever is parked waiting on them.
    private struct Mailbox {
        var pending: [HelperResponse] = []
        var waiter: CheckedContinuation<HelperResponse?, Never>?
    }
    private var isShutDown = false

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    /// Locates the helper next to the running executable, which is where SwiftPM and the
    /// app bundle both place it.
    public static func bundledExecutableURL(
        named name: String = "iPhoneDedupeHelper",
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(name)"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent(name)
        ].compactMap { $0 }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Lifecycle

    private func startIfNeeded() throws {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw DeviceHelperError.helperNotFound(executableURL.path)
        }

        let process = Process()
        process.executableURL = executableURL
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        // The helper's stderr is left attached to the app's, so its diagnostics appear in
        // the same log stream rather than being silently discarded.

        try process.run()
        self.process = process
        self.input = stdin.fileHandleForWriting
        startReading(from: stdout.fileHandleForReading)
    }

    /// Ends the helper process. The client cannot be used afterwards.
    public func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        try? send(.shutdown)
        try? input?.close()
        input = nil
        // A helper that ignores `shutdown` must not outlive the app and keep holding the
        // device, so termination is not left to good behaviour.
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        finishStream()
    }

    // MARK: - Requests

    public func scan(timeout: Duration = .seconds(120)) async throws -> DeviceCatalogSnapshot {
        try await perform(.scan(timeoutSeconds: timeout.wireSeconds)) { response in
            guard case let .scanned(snapshot) = response else { return nil }
            return snapshot
        }
    }

    public func thumbnailData(
        for token: DeviceFileToken,
        maxPixelSize: Int? = nil,
        timeout: Duration = .seconds(20)
    ) async throws -> Data {
        try await perform(
            .thumbnail(token: token, maxPixelSize: maxPixelSize, timeoutSeconds: timeout.wireSeconds)
        ) { response in
            guard case let .thumbnail(data) = response else { return nil }
            return data
        }
    }

    public func metadata(
        for token: DeviceFileToken,
        timeout: Duration = .seconds(20)
    ) async throws -> MediaMetadataSummary? {
        try await perform(.metadata(token: token, timeoutSeconds: timeout.wireSeconds)) { response in
            guard case let .metadata(summary) = response else { return nil }
            return .some(summary)
        }
    }

    public func download(
        _ tokens: [DeviceFileToken],
        stagingDirectory: URL,
        timeout: Duration = .seconds(120),
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil
    ) async throws -> DeviceGatewayImportSummary {
        try await perform(
            .download(
                tokens: tokens,
                destination: stagingDirectory,
                timeoutSeconds: timeout.wireSeconds
            ),
            onProgress: onProgress
        ) { response in
            guard case let .downloaded(summary) = response else { return nil }
            return summary
        }
    }

    public func delete(
        _ tokens: [DeviceFileToken],
        confirmed: Bool,
        timeout: Duration = .seconds(120),
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil
    ) async throws -> (summary: DeviceGatewayDeleteSummary, observedRemovedHandles: Set<UInt32>) {
        try await perform(
            .delete(tokens: tokens, confirmed: confirmed, timeoutSeconds: timeout.wireSeconds),
            onProgress: onProgress
        ) { response in
            guard case let .deleted(summary, handles) = response else { return nil }
            return (summary, handles)
        }
    }

    /// Asks the helper to cancel whatever it is doing.
    ///
    /// Written straight to the pipe rather than queued behind `perform`, because a cancel
    /// that waits for the operation it is cancelling would never arrive in time.
    public func cancel() {
        try? send(.cancel)
    }

    // MARK: - Plumbing

    private func perform<T>(
        _ request: HelperRequest,
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil,
        extract: (HelperResponse) -> T?
    ) async throws -> T {
        guard !isShutDown else { throw DeviceHelperError.helperExited("The helper was shut down.") }
        try startIfNeeded()

        let id = UUID()
        mailboxes[id] = Mailbox()
        defer { mailboxes[id] = nil }
        try send(request, id: id)

        while let response = await nextResponse(for: id) {
            switch response {
            case .ready(let version):
                guard version == HelperProtocol.version else {
                    shutdown()
                    throw DeviceHelperError.versionMismatch(
                        expected: HelperProtocol.version,
                        actual: version
                    )
                }
            case .progress(let completed, let total, let filename):
                onProgress?(DeviceBatchProgress(
                    completedItems: completed,
                    totalItems: total,
                    currentFilename: filename,
                    fractionCompleted: total > 0 ? Double(completed) / Double(total) : 0
                ))
            case .failed(let message, let isCancellation):
                throw isCancellation ? DeviceHelperError.canceled : DeviceHelperError.failed(message)
            default:
                if let value = extract(response) {
                    return value
                }
                throw DeviceHelperError.unexpectedResponse
            }
        }

        // The stream ended without a terminal response, which means the helper died.
        let detail = process?.isRunning == false
            ? "It exited with status \(process?.terminationStatus ?? -1)."
            : "The connection closed."
        shutdown()
        throw DeviceHelperError.helperExited(detail)
    }

    private func send(_ request: HelperRequest, id: UUID = UUID()) throws {
        guard let input else { throw DeviceHelperError.helperExited("The helper is not running.") }
        let data = try HelperCodec.encode(HelperRequestEnvelope(id: id, payload: request))
        do {
            try input.write(contentsOf: data)
        } catch {
            throw DeviceHelperError.helperExited(error.localizedDescription)
        }
    }

    // MARK: - Response delivery

    private func nextResponse(for id: UUID) async -> HelperResponse? {
        if var mailbox = mailboxes[id], !mailbox.pending.isEmpty {
            let response = mailbox.pending.removeFirst()
            mailboxes[id] = mailbox
            return response
        }
        if isStreamFinished { return nil }
        return await withCheckedContinuation { continuation in
            mailboxes[id]?.waiter = continuation
        }
    }

    private func deliver(_ envelope: HelperResponseEnvelope) {
        // A reply whose request has already returned or been abandoned is dropped rather
        // than handed to an unrelated waiter.
        guard var mailbox = mailboxes[envelope.id] else { return }
        if let waiter = mailbox.waiter {
            mailbox.waiter = nil
            mailboxes[envelope.id] = mailbox
            waiter.resume(returning: envelope.payload)
        } else {
            mailbox.pending.append(envelope.payload)
            mailboxes[envelope.id] = mailbox
        }
    }

    private func finishStream() {
        isStreamFinished = true
        // Wake every waiter, or a request in flight when the helper died would hang.
        for (id, mailbox) in mailboxes {
            if let waiter = mailbox.waiter {
                mailboxes[id]?.waiter = nil
                waiter.resume(returning: nil)
            }
        }
    }

    /// Reads the helper's stdout on a background thread.
    ///
    /// A dedicated thread rather than `readabilityHandler`: the handler runs on a shared
    /// queue, and blocking it would stall unrelated file reads elsewhere in the app.
    private func startReading(from handle: FileHandle) {
        // The thread body must not capture the actor directly — hopping back in would send
        // a non-Sendable closure. It captures two Sendable closures instead, each of which
        // re-enters the actor on its own.
        let onResponse: @Sendable (HelperResponseEnvelope) -> Void = { [weak self] envelope in
            Task { await self?.deliver(envelope) }
        }
        let onFinish: @Sendable () -> Void = { [weak self] in
            Task { await self?.finishStream() }
        }

        let thread = Thread {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    onFinish()
                    return
                }
                buffer.append(chunk)
                for line in HelperCodec.lines(from: &buffer) {
                    guard let envelope = try? HelperCodec.decode(
                        HelperResponseEnvelope.self,
                        from: line
                    ) else { continue }
                    onResponse(envelope)
                }
            }
        }
        thread.stackSize = 512 * 1_024
        thread.start()
    }
}

extension Duration {
    /// Named `wireSeconds`, not `seconds`: a `seconds` instance property shadows
    /// `Duration.seconds(_:)` at every call site that also uses the static factory.
    var wireSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
