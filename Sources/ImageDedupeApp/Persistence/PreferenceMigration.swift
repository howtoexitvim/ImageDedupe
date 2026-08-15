import Foundation

/// Carries stored settings across a change of bundle identifier.
///
/// `UserDefaults` is keyed by bundle identifier, so renaming the app gives it a new, empty
/// domain: the duplicate rule, column order and widths, sort, and pane widths would all
/// revert on first launch. Not destructive, but it reads as "the update broke my settings",
/// and the fix is cheap.
enum PreferenceMigration {
    /// The identifier the app used before the rename to Image Dedupe.
    static let legacyBundleIdentifier = "com.shuqi.iPhoneDedupe"

    /// Marks the one-time copy as done.
    ///
    /// Migration must not repeat: otherwise a setting the user deliberately cleared would be
    /// restored from the old domain at the next launch.
    private static let completionKey = "preferences.migratedFromLegacyDomain"

    /// Only this app's own keys. AppKit stores window and split-view state under keys tied
    /// to the old identifier's view hierarchy, and copying those across would carry state
    /// that no longer describes anything.
    private static let migratedKeys = [
        "duplicateRuleFields",
        "media.column.order",
        "media.column.widths",
        "media.sort.field",
        "media.sort.order",
        "media.pane.widths",
        "media.pane.collapsed"
    ]

    static func migrateIfNeeded(
        from legacy: UserDefaults? = UserDefaults(suiteName: legacyBundleIdentifier),
        to current: UserDefaults = .standard
    ) {
        guard !current.bool(forKey: completionKey) else { return }
        current.set(true, forKey: completionKey)

        guard let legacy else { return }
        for key in migratedKeys {
            // A value already set under the new identifier wins: the user may have changed
            // it since the rename, and a stale value must not overwrite a current one.
            guard current.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key) else { continue }
            current.set(value, forKey: key)
        }
    }
}
