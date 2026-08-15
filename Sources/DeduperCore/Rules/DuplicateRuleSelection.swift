import Foundation

/// The fields the user has chosen to decide that two files are duplicates.
///
/// This is deliberately a validated type rather than a bare `Set<MediaField>`: the rule
/// drives an irreversible delete, so selections that would group unrelated files are not
/// representable at all. `init?` returns `nil` for those, and the UI keeps the previous
/// rule instead of applying them.
public struct DuplicateRuleSelection: Equatable, Sendable {
    /// Always stored in a canonical order, so ticking the same boxes in a different order
    /// produces the same rule and the same stored value.
    public let fields: [MediaField]

    /// Fields the user may choose between, in the order they are offered.
    public static let selectableFields: [MediaField] = [.name, .kind, .size, .timestamp, .duration]

    /// Name plus kind plus size: the conservative rule the app has always used.
    ///
    /// Kept as the default deliberately. Matching on name alone was requested, but an
    /// iPhone reuses names like `IMG_0001.HEIC` after a reset or a re-import, so unrelated
    /// photos collide — and the consequence here is a deletion. Anyone who wants the looser
    /// rule can untick Size, having been shown what it does.
    public static let `default` = DuplicateRuleSelection(unchecked: [.name, .kind, .size])

    private init(unchecked fields: [MediaField]) {
        self.fields = fields
    }

    /// Creates a selection, or `nil` when it does not clear the safety floor.
    ///
    /// The floor is: at least two fields, and at least one of them must distinguish
    /// *content* rather than merely bucket files. Name and duration qualify; kind, size,
    /// and timestamp do not, because thousands of files share a kind, a size, or a burst
    /// timestamp. `kind + size` is the pairing that looks reasonable and would group every
    /// 4 MB HEIC on the device into one "duplicate" set.
    public init?(fields: [MediaField]) {
        let unique = Set(fields)
        guard unique.count >= 2 else { return nil }
        guard unique.contains(.name) || unique.contains(.duration) else { return nil }

        self.fields = Self.selectableFields.filter { unique.contains($0) }
    }

    /// Whether adding or removing `field` would still leave a usable rule. Drives whether a
    /// checkbox can be unticked, so the user is stopped before the rule becomes unsafe
    /// rather than after.
    public func canToggle(_ field: MediaField) -> Bool {
        var next = Set(fields)
        if next.contains(field) {
            next.remove(field)
        } else {
            next.insert(field)
        }
        return DuplicateRuleSelection(fields: Array(next)) != nil
    }

    /// The selection with `field` toggled, or `self` when that would breach the floor.
    public func toggling(_ field: MediaField) -> DuplicateRuleSelection {
        var next = Set(fields)
        if next.contains(field) {
            next.remove(field)
        } else {
            next.insert(field)
        }
        return DuplicateRuleSelection(fields: Array(next)) ?? self
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
        fields.map(\.rawValue).joined(separator: ",")
    }

    /// Restores a stored selection, falling back to the conservative default.
    ///
    /// A value written by a future version, or a corrupted one, must never widen the rule
    /// silently — the fallback is always the stricter option.
    public init(storedValue: String) {
        let fields = storedValue
            .split(separator: ",")
            .compactMap { MediaField(rawValue: String($0)) }
        self = DuplicateRuleSelection(fields: fields) ?? .default
    }

    /// A short description of what the rule matches on, for the UI to show verbatim.
    public var summary: String {
        fields.map(\.displayName).joined(separator: " + ")
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

    /// Why a field cannot carry a rule on its own, shown next to its checkbox.
    public var ruleCaution: String? {
        switch self {
        case .kind, .size, .timestamp:
            return "Cannot identify a file on its own."
        default:
            return nil
        }
    }
}
