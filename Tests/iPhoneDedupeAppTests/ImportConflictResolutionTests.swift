import Foundation
import XCTest

@testable import DeviceMediaKit

/// Downloading several copies of one filename.
///
/// Reported on 2026-08-16: downloading a duplicate group failed on the second copy with
/// "Import blocked", because the destination already held the first. A duplicate group
/// shares a name by definition, so this is the normal case, not an edge case — and the app
/// exists to help with exactly these files.
final class ImportConflictResolutionTests: XCTestCase {
    // MARK: - Disambiguating a name

    func testAnUnusedNameIsReturnedUnchanged() {
        let name = ImportFilenameDisambiguator.uniqueFilename(for: "IMG_0001.HEIC") { _ in false }
        XCTAssertEqual(name, "IMG_0001.HEIC")
    }

    /// The counter goes before the extension, so the file keeps its type and still opens in
    /// the right app.
    func testATakenNameGainsACounterBeforeItsExtension() {
        let name = ImportFilenameDisambiguator.uniqueFilename(for: "IMG_0001.HEIC") {
            $0 == "IMG_0001.HEIC"
        }
        XCTAssertEqual(name, "IMG_0001 2.HEIC")
    }

    func testTheCounterAdvancesPastEveryTakenName() {
        let taken: Set<String> = ["IMG_0001.HEIC", "IMG_0001 2.HEIC", "IMG_0001 3.HEIC"]
        let name = ImportFilenameDisambiguator.uniqueFilename(for: "IMG_0001.HEIC") {
            taken.contains($0)
        }
        XCTAssertEqual(name, "IMG_0001 4.HEIC")
    }

    func testAFilenameWithoutAnExtensionStillDisambiguates() {
        let name = ImportFilenameDisambiguator.uniqueFilename(for: "LIVEPHOTO") { $0 == "LIVEPHOTO" }
        XCTAssertEqual(name, "LIVEPHOTO 2")
    }

    /// Only the last extension is treated as the extension, so a compound name keeps its
    /// full identity.
    func testACompoundExtensionKeepsItsStem() {
        let name = ImportFilenameDisambiguator.uniqueFilename(for: "clip.tar.gz") { $0 == "clip.tar.gz" }
        XCTAssertEqual(name, "clip.tar 2.gz")
    }

    // MARK: - The choice itself

    /// Replace is the only option that can destroy something, so it must be the only one
    /// flagged. The flag drives the confirmation, so getting it wrong would either nag on a
    /// safe choice or wave through a destructive one.
    func testOnlyReplaceIsMarkedDestructive() {
        XCTAssertTrue(ImportConflictResolution.replace.isDestructive)
        XCTAssertFalse(ImportConflictResolution.keepBoth.isDestructive)
        XCTAssertFalse(ImportConflictResolution.skip.isDestructive)
    }

    /// There is deliberately no default: overwriting destroys and skipping loses data the
    /// user asked for, so the app must ask rather than choose.
    func testEveryResolutionIsOffered() {
        XCTAssertEqual(
            Set(ImportConflictResolution.allCases),
            [.keepBoth, .replace, .skip]
        )
    }

    func testResolutionsSurviveARoundTripForPersistence() throws {
        for resolution in ImportConflictResolution.allCases {
            let encoded = try JSONEncoder().encode(resolution)
            let decoded = try JSONDecoder().decode(ImportConflictResolution.self, from: encoded)
            XCTAssertEqual(decoded, resolution)
        }
    }
}
