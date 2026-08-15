import Foundation
import XCTest

@testable import ImageDedupeApp

/// Renaming the app must not lose the user's operation history.
///
/// The results store lives in a directory named after the app. Renaming it to "Image Dedupe"
/// without moving the old one would leave every delete audit unreadable — the records would
/// still be on disk, but the app would look in a new empty folder and report none. Delete
/// audits are the record of what was removed from a device, so silently losing them is worse
/// than most crashes.
final class StoreMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("store-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    private func write(_ contents: String, toDirectory name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("operation-results.json")
        try Data(contents.utf8).write(to: file)
        return file
    }

    /// The rename case: history written under the old name is adopted under the new one.
    func testHistoryFromTheOldNameIsAdopted() throws {
        _ = try write(#"{"records":[]}"#, toDirectory: "iPhone Dedupe")

        let resolved = OperationResultStore.resolveStoreURL(
            in: root,
            currentDirectory: "Image Dedupe",
            legacyDirectories: ["iPhone Dedupe"]
        )

        XCTAssertEqual(
            resolved.deletingLastPathComponent().lastPathComponent,
            "Image Dedupe",
            "The store must end up under the current name."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resolved.path),
            "The old records must have been moved, not abandoned."
        )
    }

    /// A fresh install has nothing to migrate and must simply use the new location.
    func testAFreshInstallUsesTheCurrentDirectory() {
        let resolved = OperationResultStore.resolveStoreURL(
            in: root,
            currentDirectory: "Image Dedupe",
            legacyDirectories: ["iPhone Dedupe"]
        )

        XCTAssertEqual(resolved.deletingLastPathComponent().lastPathComponent, "Image Dedupe")
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolved.path))
    }

    /// Existing data under the current name always wins. Overwriting it with older records
    /// from a previous name would destroy the newer history.
    func testCurrentDataIsNeverOverwrittenByLegacyData() throws {
        let current = try write(#"{"records":["current"]}"#, toDirectory: "Image Dedupe")
        _ = try write(#"{"records":["legacy"]}"#, toDirectory: "iPhone Dedupe")

        let resolved = OperationResultStore.resolveStoreURL(
            in: root,
            currentDirectory: "Image Dedupe",
            legacyDirectories: ["iPhone Dedupe"]
        )

        XCTAssertEqual(resolved, current)
        XCTAssertEqual(
            try String(contentsOf: resolved, encoding: .utf8),
            #"{"records":["current"]}"#,
            "Newer history must survive a legacy folder still being present."
        )
    }

    /// Migration copies rather than moves, so an interrupted run cannot lose the original.
    func testTheLegacyFileIsLeftInPlaceAsABackup() throws {
        let legacy = try write(#"{"records":["legacy"]}"#, toDirectory: "iPhone Dedupe")

        _ = OperationResultStore.resolveStoreURL(
            in: root,
            currentDirectory: "Image Dedupe",
            legacyDirectories: ["iPhone Dedupe"]
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: legacy.path),
            "The original stays put; a copy is cheap and a lost audit trail is not."
        )
    }
}
