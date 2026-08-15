import DeduperCore
import Foundation
import XCTest

@testable import DeviceMediaKit

/// The app builds `Dictionary(uniqueKeysWithValues:)` keyed by `model.id`, which **traps**
/// on a repeated key. So a catalog containing two files with the same id does not degrade
/// gracefully — it terminates the process.
///
/// That is the crash reported on 2026-08-15 after deleting several photos at once: a real
/// device produced two files sharing the unassigned object handle `0` and the name
/// `QVKQ5385.JPG`, giving `0-QVKQ5385.JPG` twice.
///
/// `DeviceMediaFileIdentity` handles every case it can see, but it is given one file at a
/// time. `DeviceCatalogIndex` is the only place with a view of the whole catalog, so the
/// guarantee lives there: no device quirk may be able to crash the app.
final class CatalogIdentityUniquenessTests: XCTestCase {
    private func catalogFile(
        id: String,
        name: String,
        handle: UInt32,
        generation: UUID = UUID()
    ) -> DeviceCatalogFile {
        DeviceCatalogFile(
            model: DeviceMediaFile(
                id: id,
                name: name,
                kind: "JPG",
                size: 1_000,
                timestamp: nil,
                width: nil,
                height: nil
            ),
            token: DeviceFileToken(
                generation: generation,
                objectHandle: handle,
                fingerprint: DeviceFileFingerprint(
                    name: name,
                    kind: "JPG",
                    size: 1_000,
                    timestamp: nil
                )
            )
        )
    }

    /// The exact catalog that crashed the app.
    func testTwoFilesSharingAnIdBothSurviveWithDistinctIds() {
        var index = DeviceCatalogIndex()

        XCTAssertTrue(index.insert(catalogFile(id: "0-QVKQ5385.JPG", name: "QVKQ5385.JPG", handle: 0)))
        XCTAssertTrue(index.insert(catalogFile(id: "0-QVKQ5385.JPG", name: "QVKQ5385.JPG", handle: 0)))

        XCTAssertEqual(index.files.count, 2, "Neither file may be silently dropped.")
        XCTAssertEqual(
            Set(index.files.map(\.model.id)).count,
            2,
            "Duplicate ids trap Dictionary(uniqueKeysWithValues:)."
        )
    }

    /// The property the crash actually depends on, stated directly: building the dictionary
    /// the view model builds must not trap.
    func testTheCatalogCanBeKeyedByIdWithoutTrapping() {
        var index = DeviceCatalogIndex()
        for _ in 0..<5 {
            _ = index.insert(catalogFile(id: "0-SAME.JPG", name: "SAME.JPG", handle: 0))
        }

        // This is the call that crashed in `deriveVisibleItems`.
        let byID = Dictionary(uniqueKeysWithValues: index.files.map { ($0.model.id, $0) })
        XCTAssertEqual(byID.count, index.files.count)
    }

    /// Disambiguating must not disturb files that were already unique.
    func testUniqueIdsArePreservedExactly() {
        var index = DeviceCatalogIndex()
        _ = index.insert(catalogFile(id: "7-A.JPG", name: "A.JPG", handle: 7))
        _ = index.insert(catalogFile(id: "8-B.JPG", name: "B.JPG", handle: 8))

        XCTAssertEqual(index.files.map(\.model.id), ["7-A.JPG", "8-B.JPG"])
    }

    /// Token-level de-duplication was **removed** on 2026-08-16, deliberately.
    ///
    /// It assumed a repeated token meant the framework had reported one file twice. On a
    /// device that assigns no object handles that assumption is false: a token degenerates
    /// to its fingerprint, so two real duplicates share one. Dropping the second hid exactly
    /// the files this app exists to find — 26 of them on the reporting user's device.
    ///
    /// The catalog now keeps both and disambiguates their ids instead. Over-reporting a
    /// duplicate is recoverable — the user sees two rows and decides — whereas silently
    /// discarding one is not: nothing downstream can recover a file the catalog never
    /// mentioned.
    func testTwoEntriesWithOneTokenAreBothKeptWithDistinctIDs() {
        var index = DeviceCatalogIndex()
        let file = catalogFile(id: "7-A.JPG", name: "A.JPG", handle: 7)

        XCTAssertTrue(index.insert(file))
        XCTAssertTrue(index.insert(file))
        XCTAssertEqual(index.files.count, 2)
        XCTAssertEqual(Set(index.files.map(\.model.id)).count, 2)
    }

    /// The 26 missing files reported on 2026-08-16.
    ///
    /// Image Capture listed 3,978 entries where the app kept 3,952. Every file on that
    /// device carries the unassigned object handle `0`, so a token degenerates to its
    /// fingerprint alone — and two genuinely separate files with the same name, kind, size,
    /// and timestamp then share a token, so the second was dropped as a repeat.
    ///
    /// Those are exactly the files this app exists to find. Dropping a duplicate before the
    /// planner sees it is worse than any display bug: the user is told they have no
    /// duplicates precisely when they do.
    func testTwoDistinctFilesSharingATokenAreBothKept() {
        var index = DeviceCatalogIndex()
        // One generation, as a real scan has: with every handle 0 the tokens are then
        // byte-identical, which is what made the second file vanish.
        let generation = UUID()
        let first = catalogFile(id: "0-A.JPG", name: "A.JPG", handle: 0, generation: generation)
        let second = catalogFile(id: "0-A.JPG", name: "A.JPG", handle: 0, generation: generation)

        XCTAssertTrue(index.insert(first))
        XCTAssertTrue(
            index.insert(second),
            "A second file with the same token is a duplicate to report, not a repeat to drop."
        )
        XCTAssertEqual(index.files.count, 2)
        XCTAssertEqual(Set(index.files.map(\.model.id)).count, 2, "Ids must still be unique.")
    }

    /// The catalog must survive being keyed by id, which is what forced the de-duplication
    /// in the first place. Both properties have to hold at once.
    func testBothCopiesSurviveAndTheCatalogStillKeysByID() {
        var index = DeviceCatalogIndex()
        let generation = UUID()
        for _ in 0..<4 {
            _ = index.insert(catalogFile(
                id: "0-SAME.JPG",
                name: "SAME.JPG",
                handle: 0,
                generation: generation
            ))
        }

        XCTAssertEqual(index.files.count, 4, "Four real files, four rows.")
        let byID = Dictionary(uniqueKeysWithValues: index.files.map { ($0.model.id, $0) })
        XCTAssertEqual(byID.count, 4)
    }

    /// No source file may build a trapping dictionary over device-derived keys.
    ///
    /// This class of crash has now killed the app twice: once keyed by `model.id` after the
    /// identity change, and once keyed by token after duplicates stopped being dropped. Both
    /// times the keys came from the device, where uniqueness cannot be assumed.
    /// `uniqueKeysWithValues` traps rather than degrading, so a device quirk becomes a
    /// crash. The merging initializer is required instead.
    func testNoSourceFileUsesATrappingDictionaryInitializer() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ImageDedupeAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources")

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (number, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip prose: several comments name the API while explaining these crashes.
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                if line.contains("uniqueKeysWithValues") {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Use Dictionary(_:uniquingKeysWith:) for device-derived keys. Found: \(offenders)"
        )
    }
}
