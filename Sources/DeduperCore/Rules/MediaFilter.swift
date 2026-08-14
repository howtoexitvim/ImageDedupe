public enum MediaFilter: Equatable, Sendable {
    case nameContains(String)
    case kindIn(Set<String>)
    case sizeBetween(min: Int64?, max: Int64?)

    public func matches(_ file: DeviceMediaFile) -> Bool {
        switch self {
        case .nameContains(let query):
            guard !query.isEmpty else {
                return true
            }
            return file.name.lowercased().contains(query.lowercased())
        case .kindIn(let kinds):
            guard !kinds.isEmpty else {
                return true
            }
            let normalizedKinds = Set(kinds.map { $0.uppercased() })
            return normalizedKinds.contains(file.kind.uppercased())
        case .sizeBetween(let min, let max):
            if let min, file.size < min {
                return false
            }
            if let max, file.size > max {
                return false
            }
            return true
        }
    }
}
