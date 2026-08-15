public struct DeviceMediaFile: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let size: Int64
    public let timestamp: String?
    public let width: Int?
    public let height: Int?
    public let duration: Double?
    public let location: String?
    public let groupUUID: String?
    public let burstUUID: String?
    public let isRaw: Bool
    public let isHighFramerate: Bool
    public let isTimeLapse: Bool

    public init(
        id: String,
        name: String,
        kind: String,
        size: Int64,
        timestamp: String?,
        width: Int?,
        height: Int?,
        duration: Double? = nil,
        location: String? = nil,
        groupUUID: String? = nil,
        burstUUID: String? = nil,
        isRaw: Bool = false,
        isHighFramerate: Bool = false,
        isTimeLapse: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.duration = duration
        self.location = location
        self.groupUUID = groupUUID
        self.burstUUID = burstUUID
        self.isRaw = isRaw
        self.isHighFramerate = isHighFramerate
        self.isTimeLapse = isTimeLapse
    }
}
