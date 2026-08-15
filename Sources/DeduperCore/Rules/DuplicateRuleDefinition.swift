public struct DuplicateRuleDefinition: Equatable, Sendable {
    public let id: String
    public let fields: [RuleField]

    public init(id: String, fields: [RuleField]) {
        self.id = id
        self.fields = fields
    }

    public func key(for file: DeviceMediaFile) -> String? {
        // No fields means nothing has been said about what makes two files the same, so
        // nothing is grouped. Without this the loop below produces an empty key for *every*
        // file, which reads as "they are all identical" — the most dangerous possible
        // interpretation of an empty rule, and one that feeds a delete.
        guard !fields.isEmpty else { return nil }

        var parts: [String] = []

        for field in fields {
            guard let value = field.value(from: file), !value.isEmpty else {
                return nil
            }
            parts.append(value)
        }

        return parts.joined(separator: "|")
    }
}

public struct RuleField: Equatable, Sendable {
    public let field: MediaField
    public let normalizers: [FieldNormalizer]

    public init(field: MediaField, normalizers: [FieldNormalizer] = []) {
        self.field = field
        self.normalizers = normalizers
    }

    public func value(from file: DeviceMediaFile) -> String? {
        guard var value = field.rawValue(from: file) else {
            return nil
        }

        for normalizer in normalizers {
            value = normalizer.apply(to: value)
        }

        return value
    }
}
