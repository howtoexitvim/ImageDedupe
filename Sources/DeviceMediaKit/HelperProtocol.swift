import DeduperCore
import Foundation

/// The line-delimited JSON protocol spoken between the app and a device helper process.
///
/// A helper exists because ImageCaptureCore delivers a device's content exactly once per
/// `ICCameraDevice` object, through `deviceDidBecomeReady(withCompleteContentCatalog:)`.
/// A process that already holds a device can never obtain a second catalog for it — closing
/// and reopening the session leaves `mediaFiles` permanently empty, and the device is not
/// re-advertised to a browser this process already owns. Measured on 2026-08-15: two scans
/// in one process reported an identical catalog across a photo being taken, while a fresh
/// process saw the change immediately.
///
/// So "rescan" is spelled "new process". Each helper serves exactly one catalog generation
/// and owns the `ICCameraFile` objects belonging to it, which is also what keeps tokens
/// meaningful: a token only ever resolves in the process that produced it.
public enum HelperProtocol {
    /// Bumped when the message shape changes, so a stale helper binary is rejected rather
    /// than silently misparsed.
    public static let version = 1

    /// The id the helper's unsolicited `ready` greeting carries.
    ///
    /// It answers no request, so it needs an id no request will generate. Waiters ignore
    /// it; a mismatched protocol version is caught when the first real request is sent.
    public static let greetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

/// A request sent from the app to the helper, one JSON object per line.
public enum HelperRequest: Codable, Sendable {
    case scan(timeoutSeconds: Double)
    case thumbnail(token: DeviceFileToken, maxPixelSize: Int?, timeoutSeconds: Double)
    case metadata(token: DeviceFileToken, timeoutSeconds: Double)
    case download(tokens: [DeviceFileToken], destination: URL, timeoutSeconds: Double)
    case delete(tokens: [DeviceFileToken], confirmed: Bool, timeoutSeconds: Double)
    /// Cancels the in-flight operation. Sent out of band, so the helper must read requests
    /// concurrently with executing one.
    case cancel
    case shutdown
}

/// A request paired with the identifier its responses must carry.
///
/// The app issues several requests at once — a thumbnail per visible tile, the inspector's
/// preview, metadata, and possibly a download — onto one pipe. Without an identifier, each
/// waiter simply took the next response to arrive, so a thumbnail could consume a
/// download's reply (reported as "the device helper sent an unexpected response") and a
/// tile could be handed another tile's image. Correlation is what makes concurrent requests
/// safe on a single connection.
public struct HelperEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let id: UUID
    public let payload: Payload

    public init(id: UUID, payload: Payload) {
        self.id = id
        self.payload = payload
    }
}

public typealias HelperRequestEnvelope = HelperEnvelope<HelperRequest>
public typealias HelperResponseEnvelope = HelperEnvelope<HelperResponse>

/// A response sent from the helper to the app, one JSON object per line.
///
/// `progress` may be emitted any number of times before exactly one terminal response for
/// the request that is in flight.
public enum HelperResponse: Codable, Sendable {
    case ready(version: Int)
    case scanned(snapshot: DeviceCatalogSnapshot)
    case thumbnail(data: Data)
    case metadata(summary: MediaMetadataSummary?)
    /// The gateway's own summary types cross the wire unchanged. They are already
    /// `Codable`, and translating them into a flattened shape would be a second place for
    /// "succeeded" and "was observed removed" to drift apart.
    case downloaded(summary: DeviceGatewayImportSummary)
    case deleted(summary: DeviceGatewayDeleteSummary, observedRemovedHandles: Set<UInt32>)
    case progress(completed: Int, total: Int, filename: String?)
    case failed(message: String, isCancellation: Bool)
}

/// Encodes and decodes the newline-delimited framing.
///
/// Framing is deliberately trivial — one JSON object per line — because the alternative
/// (length-prefixed binary) is harder to debug from a terminal, and these messages are
/// small and infrequent. Thumbnail bytes travel base64-encoded inside the JSON, which is
/// the one place that costs anything; at preview sizes it is immaterial.
public enum HelperCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }

    /// Splits a buffer into complete lines, returning the remainder.
    ///
    /// A pipe read can deliver a partial line, several lines at once, or both, so the
    /// caller must keep the remainder and prepend it to the next read.
    public static func lines(from buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<index]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer = Data(buffer[buffer.index(after: index)...])
        }
        return lines
    }
}
