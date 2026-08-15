import Foundation

/// The fields the user has chosen to decide that two files are duplicates.
///
/// Every combination is permitted, including a single field and none at all. A rule only
/// changes what Duplicates *shows*; the delete confirmation still names exactly which files
/// will be removed, and that is what guards the destructive step.
public struct DuplicateRuleSelection: Equatable, Sendable {
    /// Always stored in a canonical order, so ticking the same boxes in a different order
    /// produces the same rule and the same stored value.
    public let fields: [MediaField]

    /// Fields the user may choose between, in the order they are offered.
    public static let selectableFields: [MediaField] = [.name, .kind, .size, .timestamp, .duration]

    /// Name plus kind plus size: the rule the app has always used, kept as the starting
    /// point because it is the most conservative of the useful ones.
    public static let `default` = DuplicateRuleSelection(fields: [.name, .kind, .size])

    /// Creates a selection from any set of fields.
    ///
    /// Deliberately unrestricted, at the user's direction after measuring what each rule
    /// would actually do to their catalog: on 3,955 files, matching on Name alone marked
    /// exactly the same single file as Name+Kind+Size, so the name-collision risk that had
    /// justified a floor did not exist in practice.
    ///
    /// Looser rules do differ — Date alone marked 585 files and Size alone 20 — but the
    /// protection against those is the delete confirmation, which names exactly what will
    /// be removed and is unchanged. A rule is a *view*, not an action: nothing is deleted
    /// until the user confirms a specific set of files.
    ///
    /// An empty selection is legal and simply groups nothing.
    public init(fields: [MediaField]) {
        let unique = Set(fields)
        self.fields = Self.selectableFields.filter { unique.contains($0) }
    }

    /// The selection with `field` toggled. Every combination is permitted.
    public func toggling(_ field: MediaField) -> DuplicateRuleSelection {
        var next = Set(fields)
        if next.contains(field) {
            next.remove(field)
        } else {
            next.insert(field)
        }
        return DuplicateRuleSelection(fields: Array(next))
    }

    public var definition: DuplicateRuleDefinition {
        DuplicateRuleDefinition(
            id: storedValue,
            fields: fields.map { field in
                switch field {
                case .name:
                    // Case-insensitive, so `IMG_0001.HEIC` and `img_0001.heic` are one file.
                    return RuleField(field: .name, normalizers: [.lowercase])
                case .kind:
                    return RuleField(field: .kind, normalizers: [.uppercase])
                default:
                    return RuleField(field: field)
                }
            }
        )
    }

    // MARK: - Persistence

    public var storedValue: String {
        fields.isEmpty ? Self.emptyMarker : fields.map(\.rawValue).joined(separator: ",")
    }

    /// Marker for a deliberately empty rule, so it survives a round trip instead of being
    /// mistaken for "nothing stored" and silently reset to the default.
    private static let emptyMarker = "none"

    /// Restores a stored selection.
    ///
    /// Anything unparseable falls back to the default rather than to an arbitrary rule; a
    /// deliberately empty selection is preserved.
    public init(storedValue: String) {
        if storedValue == Self.emptyMarker {
            self = DuplicateRuleSelection(fields: [])
            return
        }
        let fields = storedValue
            .split(separator: ",")
            .compactMap { MediaField(rawValue: String($0)) }
        self = fields.isEmpty ? .default : DuplicateRuleSelection(fields: fields)
    }

    /// A short description of what the rule matches on, for the UI to show verbatim.
    public var summary: String {
        fields.isEmpty ? "No fields selected" : fields.map(\.displayName).joined(separator: " + ")
    }
}

extension MediaField {
    public var displayName: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .size: return "Size"
        case .timestamp: return "Date"
        case .duration: return "Duration"
        case .width: return "Width"
        case .height: return "Height"
        }
    }

}
