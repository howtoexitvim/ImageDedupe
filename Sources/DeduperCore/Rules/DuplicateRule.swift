public enum DuplicateRule: String, Sendable {
    case nameKindSize
    case timestampKindSize

    public var definition: DuplicateRuleDefinition {
        switch self {
        case .nameKindSize:
            return DuplicateRuleDefinition(
                id: rawValue,
                fields: [
                    RuleField(field: .name, normalizers: [.lowercase]),
                    RuleField(field: .kind, normalizers: [.uppercase]),
                    RuleField(field: .size),
                ]
            )
        case .timestampKindSize:
            return DuplicateRuleDefinition(
                id: rawValue,
                fields: [
                    RuleField(field: .timestamp),
                    RuleField(field: .kind, normalizers: [.uppercase]),
                    RuleField(field: .size),
                ]
            )
        }
    }
}
