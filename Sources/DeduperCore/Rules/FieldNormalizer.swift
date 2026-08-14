public enum FieldNormalizer: String, Sendable {
    case lowercase
    case uppercase

    public func apply(to value: String) -> String {
        switch self {
        case .lowercase:
            return value.lowercased()
        case .uppercase:
            return value.uppercased()
        }
    }
}
