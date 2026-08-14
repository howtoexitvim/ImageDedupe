public enum MediaField: String, Sendable {
    case name
    case kind
    case size
    case timestamp
    case width
    case height

    public func rawValue(from file: DeviceMediaFile) -> String? {
        switch self {
        case .name:
            return file.name
        case .kind:
            return file.kind
        case .size:
            return String(file.size)
        case .timestamp:
            return file.timestamp
        case .width:
            return file.width.map(String.init)
        case .height:
            return file.height.map(String.init)
        }
    }
}
