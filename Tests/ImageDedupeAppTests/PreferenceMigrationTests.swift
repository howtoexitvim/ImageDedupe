import Foundation
import XCTest

@testable import ImageDedupeApp

/// Changing the bundle identifier gives the app a new `UserDefaults` domain, so every stored
/// preference — duplicate rule, column widths and order, sort, pane widths — would silently
/// revert to defaults on first launch after the rename.
///
/// That is not data loss in the serious sense, but it is the kind of change that reads as
/// "the update broke my settings", so the old domain is read once and carried over.
final class PreferenceMigrationTests: XCTestCase {
    private var legacyName: String!
    private var currentName: String!
    private var legacy: UserDefaults!
    private var current: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let unique = UUID().uuidString
        legacyName = "legacy-\(unique)"
        currentName = "current-\(unique)"
        legacy = try XCTUnwrap(UserDefaults(suiteName: legacyName))
        current = try XCTUnwrap(UserDefaults(suiteName: currentName))
    }

    override func tearDownWithError() throws {
        legacy.removePersistentDomain(forName: legacyName)
        current.removePersistentDomain(forName: currentName)
        try super.tearDownWithError()
    }

    func testSettingsAreCarriedOverFromTheOldDomain() {
        legacy.set("name,kind", forKey: "duplicateRuleFields")
        legacy.set(["a", "b"], forKey: "media.column.order")

        PreferenceMigration.migrateIfNeeded(from: legacy, to: current)

        XCTAssertEqual(current.string(forKey: "duplicateRuleFields"), "name,kind")
        XCTAssertEqual(current.stringArray(forKey: "media.column.order"), ["a", "b"])
    }

    /// Anything already set under the new domain wins: a value the user chose *after* the
    /// rename must not be overwritten by a stale one from before it.
    func testExistingSettingsAreNotOverwritten() {
        legacy.set("name", forKey: "duplicateRuleFields")
        current.set("name,kind,size", forKey: "duplicateRuleFields")

        PreferenceMigration.migrateIfNeeded(from: legacy, to: current)

        XCTAssertEqual(current.string(forKey: "duplicateRuleFields"), "name,kind,size")
    }

    /// Migration runs once. Otherwise deliberately clearing a setting would see it restored
    /// from the old domain on the next launch.
    func testMigrationRunsOnlyOnce() {
        legacy.set("name", forKey: "duplicateRuleFields")
        PreferenceMigration.migrateIfNeeded(from: legacy, to: current)

        current.removeObject(forKey: "duplicateRuleFields")
        PreferenceMigration.migrateIfNeeded(from: legacy, to: current)

        XCTAssertNil(
            current.string(forKey: "duplicateRuleFields"),
            "A second run must not resurrect a setting the user cleared."
        )
    }

    /// Only this app's own keys move. Copying AppKit's window-frame keys across would carry
    /// state tied to the old bundle identifier's view hierarchy.
    func testUnrelatedKeysAreNotCopied() {
        legacy.set("something", forKey: "NSNavPanelExpandedSizeForOpenMode")

        PreferenceMigration.migrateIfNeeded(from: legacy, to: current)

        XCTAssertNil(current.string(forKey: "NSNavPanelExpandedSizeForOpenMode"))
    }

    /// A fresh install has nothing to copy and must not fail.
    func testAFreshInstallMigratesNothing() {
        PreferenceMigration.migrateIfNeeded(from: legacy, to: current)
        XCTAssertNil(current.string(forKey: "duplicateRuleFields"))
    }
}
