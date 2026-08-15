import DeduperCore
import Foundation

/// Remembers which fields the user chose to match duplicates on.
///
/// Persisted because re-picking the rule on every launch would be tedious, and because a
/// forgotten rule would silently revert the user to a different definition of "duplicate"
/// than the one they last reviewed under.
///
/// Reading is deliberately forgiving: `DuplicateRuleSelection(storedValue:)` falls back to
/// the conservative default for anything it cannot parse, so a value written by a future
/// version can never widen the rule behind the user's back.
final class DuplicateRulePreferences {
    private static let key = "duplicateRuleFields"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DuplicateRuleSelection {
        guard let stored = defaults.string(forKey: Self.key) else {
            return .default
        }
        return DuplicateRuleSelection(storedValue: stored)
    }

    func save(_ selection: DuplicateRuleSelection) {
        defaults.set(selection.storedValue, forKey: Self.key)
    }
}
