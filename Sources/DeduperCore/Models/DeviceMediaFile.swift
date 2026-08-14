public struct DeviceMediaFile: Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let size: Int64
    public let timestamp: String?
    public let width: Int?
    public let height: Int?

    public init(
        id: String,
        name: String,
        kind: String,
        size: Int64,
        timestamp: String?,
        width: Int?,
        height: Int?
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.timestamp = timestamp
        self.width = width
        self.height = height
    }
}
