import DeduperCore
import Foundation

/// The app's single entry point to the device, backed by one helper process at a time.
///
/// Rescanning is spelled "retire the current helper and start another", because
/// ImageCaptureCore enumerates a device once per process and never again. Every other
/// command — previews, metadata, download, delete — is routed to the *same* helper that
/// produced the catalog those tokens came from, since a token only resolves to an
/// `ICCameraFile` inside the process that created it.
///
/// That last point is why this type exists rather than a free function: it makes "which
/// process owns the live catalog" a single piece of state instead of an assumption spread
/// across call sites.
public actor DeviceSession {
    private let makeClient: @Sendable () -> DeviceHelperClient?
    private var current: DeviceHelperClient?

    /// The generation of the catalog `current` is serving, so a command carrying a token
    /// from an older scan is refused rather than resolved against the wrong process.
    private var currentGeneration: UUID?

    public init(makeClient: (@Sendable () -> DeviceHelperClient?)? = nil) {
        self.makeClient = makeClient ?? {
            guard let url = DeviceHelperClient.bundledExecutableURL() else { return nil }
            return DeviceHelperClient(executableURL: url)
        }
    }

    /// Starts a fresh helper and returns its catalog.
    ///
    /// The previous helper is shut down first: leaving it running would keep it holding the
    /// device, and the new process would then fail to open a session.
    public func scan(timeout: Duration = .seconds(120)) async throws -> DeviceCatalogSnapshot {
        await retire()

        guard let client = makeClient() else {
            throw DeviceHelperError.helperNotFound("iPhoneDedupeHelper")
        }
        current = client

        do {
            let snapshot = try await client.scan(timeout: timeout)
            currentGeneration = snapshot.generation
            return snapshot
        } catch {
            // A failed scan leaves no usable catalog, so it must not leave a helper behind
            // holding the device against the next attempt.
            await retire()
            throw error
        }
    }

    public func thumbnailData(
        for token: DeviceFileToken,
        maxPixelSize: Int? = nil,
        timeout: Duration = .seconds(20)
    ) async throws -> Data {
        try await client(for: token).thumbnailData(
            for: token,
            maxPixelSize: maxPixelSize,
            timeout: timeout
        )
    }

    public func metadata(
        for token: DeviceFileToken,
        timeout: Duration = .seconds(20)
    ) async throws -> MediaMetadataSummary? {
        try await client(for: token).metadata(for: token, timeout: timeout)
    }

    public func download(
        _ tokens: [DeviceFileToken],
        stagingDirectory: URL,
        timeout: Duration = .seconds(120),
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil
    ) async throws -> DeviceGatewayImportSummary {
        guard let first = tokens.first else { return DeviceGatewayImportSummary() }
        return try await client(for: first).download(
            tokens,
            stagingDirectory: stagingDirectory,
            timeout: timeout,
            onProgress: onProgress
        )
    }

    public func delete(
        _ tokens: [DeviceFileToken],
        confirmed: Bool,
        timeout: Duration = .seconds(120),
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil
    ) async throws -> (summary: DeviceGatewayDeleteSummary, observedRemovedHandles: Set<UInt32>) {
        guard let first = tokens.first else {
            return (DeviceGatewayDeleteSummary(), [])
        }
        return try await client(for: first).delete(
            tokens,
            confirmed: confirmed,
            timeout: timeout,
            onProgress: onProgress
        )
    }

    public func cancel() async {
        await current?.cancel()
    }

    /// Ends the current helper, releasing the device.
    public func retire() async {
        await current?.shutdown()
        current = nil
        currentGeneration = nil
    }

    /// The helper that owns `token`, or an error if it belongs to an older scan.
    ///
    /// Refusing here rather than letting the helper fail keeps the failure legible: a stale
    /// token is a "scan again" situation, not a device fault.
    private func client(for token: DeviceFileToken) throws -> DeviceHelperClient {
        guard let current, let currentGeneration else {
            throw DeviceHelperError.failed("Scan the device before running this command.")
        }
        guard token.generation == currentGeneration else {
            throw DeviceHelperError.failed(
                "This item belongs to an older device scan. Scan again and retry."
            )
        }
        return current
    }
}
