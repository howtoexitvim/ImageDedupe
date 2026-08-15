import Foundation

public struct DeviceFileFingerprint: Hashable, Codable, Sendable {
    public let name: String
    public let kind: String
    public let size: Int64
    public let timestamp: Date?

    public init(name: String, kind: String, size: Int64, timestamp: Date?) {
        self.name = Self.normalizeName(name)
        self.kind = Self.normalizeKind(kind)
        self.size = size
        self.timestamp = timestamp
    }

    private static func normalizeName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    private static func normalizeKind(_ kind: String) -> String {
        kind
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .uppercased()
    }
}

public struct DeviceFileToken: Hashable, Codable, Sendable {
    public let generation: UUID
    public let objectHandle: UInt32
    public let fingerprint: DeviceFileFingerprint

    public init(
        generation: UUID,
        objectHandle: UInt32,
        fingerprint: DeviceFileFingerprint
    ) {
        self.generation = generation
        self.objectHandle = objectHandle
        self.fingerprint = fingerprint
    }
}
