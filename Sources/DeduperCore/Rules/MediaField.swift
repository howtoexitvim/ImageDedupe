public enum MediaField: String, Sendable {
    case name
    case kind
    case size
    case timestamp
    case duration
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
        case .duration:
            // Rounded to a tenth of a second: two copies of the same clip can differ in the
            // last decimal place, and an exact match on a Double would miss them.
            return file.duration.map { String(format: "%.1f", $0) }
        case .width:
            return file.width.map(String.init)
        case .height:
            return file.height.map(String.init)
        }
    }
}
