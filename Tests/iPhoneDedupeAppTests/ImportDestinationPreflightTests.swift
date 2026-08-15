import Foundation
import XCTest
@testable import iPhoneDedupeApp

final class ImportDestinationPreflightTests: XCTestCase {
    private let items = [
        ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600),
        ImportDestinationPreflight.Item(filename: "IMG_0002.MOV", size: 400)
    ]

    func testReadyWhenDestinationPassesEveryCheck() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(availableCapacity: 2_000)
        )

        XCTAssertEqual(result, .ready(requiredBytes: 1_600, availableBytes: 2_000))
    }

    func testNonDirectoryIsBlocked() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(isDirectory: false)
        )

        XCTAssertEqual(result, .blocked(.notDirectory))
    }

    func testNonLocalVolumeIsBlocked() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(isLocalVolume: false)
        )

        XCTAssertEqual(result, .blocked(.nonLocalVolume))
    }

    func testUnwritableDirectoryIsBlocked() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(isWritable: false)
        )

        XCTAssertEqual(result, .blocked(.notWritable))
    }

    func testUnknownCapacityIsBlockedRatherThanGuessed() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(availableCapacity: nil)
        )

        XCTAssertEqual(result, .blocked(.capacityUnavailable))
    }

    func testInsufficientCapacityReportsRequiredAndAvailableBytes() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(availableCapacity: 1_599)
        )

        XCTAssertEqual(result, .blocked(.insufficientSpace(requiredBytes: 1_600, availableBytes: 1_599)))
    }

    func testDifferentVolumeRequiresOneLargestFileOfStagingCapacity() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(
                availableCapacity: 1_000,
                stagingSharesDestinationVolume: false,
                stagingAvailableCapacity: 599
            )
        )

        XCTAssertEqual(result, .blocked(.insufficientStagingSpace(requiredBytes: 600, availableBytes: 599)))
    }

    /// Selecting a whole duplicate group and pressing Download.
    ///
    /// Reported on 2026-08-16: Cmd-A then Download was blocked as a collision even with an
    /// empty destination. Duplicates are *by definition* several files sharing a name, so
    /// treating same-named selections as a collision made downloading a duplicate group
    /// impossible — the one thing the user most wants to do before deleting one.
    ///
    /// Two copies of one file are not a reason to refuse the batch: they are the reason it
    /// exists. The destination still cannot be overwritten, so the safety property that
    /// matters is untouched.
    func testDownloadingSeveralCopiesOfOneFileIsAllowed() {
        let duplicates = [
            ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600),
            ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600)
        ]

        let result = ImportDestinationPreflight.evaluate(
            items: duplicates,
            facts: facts(availableCapacity: 5_000, existingFilenames: [])
        )

        guard case .ready = result else {
            return XCTFail("A duplicate group must be downloadable, got \(result)")
        }
    }

    /// An existing file no longer blocks the batch: the app asks per file instead.
    ///
    /// Nothing is overwritten as a result — `DestinationCommitter` publishes with
    /// `RENAME_EXCL` unless the user chose Replace for that specific conflict.
    func testAnExistingFileDoesNotBlockADuplicateGroup() {
        let duplicates = [
            ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600),
            ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600)
        ]

        let result = ImportDestinationPreflight.evaluate(
            items: duplicates,
            facts: facts(availableCapacity: 5_000, existingFilenames: ["IMG_0001.HEIC"])
        )

        guard case .ready = result else {
            return XCTFail("Name conflicts are resolved per file now, got \(result)")
        }
    }

    /// Capacity must count every copy, not one per name, or a large duplicate group could
    /// be admitted onto a disk that cannot hold it.
    func testCapacityCountsEveryCopyOfADuplicate() {
        let duplicates = [
            ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600),
            ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 600)
        ]

        let result = ImportDestinationPreflight.evaluate(
            items: duplicates,
            facts: facts(availableCapacity: 900, existingFilenames: [])
        )

        guard case .blocked(.insufficientSpace) = result else {
            return XCTFail("Both copies must be counted, got \(result)")
        }
    }

    /// An existing filename is admitted so the app can ask about it per file. Refusing here
    /// made the conflict prompt unreachable in the case it exists for.
    func testExistingFilenameIsAdmittedForPerFileResolution() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(existingFilenames: ["IMG_0002.MOV"])
        )

        guard case .ready = result else {
            return XCTFail("Expected the batch to start, got \(result)")
        }
    }

    /// Selecting two files whose names differ only by case is **allowed** to start.
    ///
    /// This previously blocked the whole batch, which also blocked every duplicate group —
    /// the reason Cmd-A then Download failed against an empty folder on 2026-08-16.
    ///
    /// Nothing is overwritten as a result. `DestinationCommitter` publishes each file with
    /// `O_CREAT | O_EXCL`, so the second copy fails its own commit and is reported against
    /// that file, rather than the batch being refused before anything is downloaded. That is
    /// also the better report: the user learns which copy landed instead of being told to
    /// deselect something they cannot identify.
    func testCaseInsensitiveDuplicateNamesNoLongerBlockTheBatch() {
        let duplicateItems = [
            ImportDestinationPreflight.Item(filename: "same.heic", size: 10),
            ImportDestinationPreflight.Item(filename: "SAME.HEIC", size: 10)
        ]

        let result = ImportDestinationPreflight.evaluate(
            items: duplicateItems,
            facts: facts()
        )

        guard case .ready = result else {
            return XCTFail("A same-named pair must be allowed to start, got \(result)")
        }
    }

    /// A case-insensitive match against the destination is a conflict to *ask* about, not a
    /// reason to refuse the batch.
    func testACaseInsensitiveMatchDoesNotBlockTheBatch() {
        let result = ImportDestinationPreflight.evaluate(
            items: [ImportDestinationPreflight.Item(filename: "same.heic", size: 10)],
            facts: facts(existingFilenames: ["SAME.HEIC"])
        )

        guard case .ready = result else {
            return XCTFail("The prompt handles this per file, got \(result)")
        }
    }

    func testInspectAcceptsARealWritableLocalDirectoryAndRemovesItsProbe() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = ImportDestinationPreflight.inspect(
            destination: directory,
            items: [ImportDestinationPreflight.Item(filename: "tiny.heic", size: 1)]
        )

        guard case .ready = result else {
            return XCTFail("expected a real local temporary directory to pass, got \(result)")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    /// The same against a real folder: an existing file is reported as ready, and resolved
    /// when that file is reached.
    func testInspectAdmitsARealExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("existing".utf8).write(to: directory.appendingPathComponent("IMG_0001.HEIC"))

        let result = ImportDestinationPreflight.inspect(
            destination: directory,
            items: [ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 1)]
        )

        guard case .ready = result else {
            return XCTFail("Expected the batch to start, got \(result)")
        }
    }

    private func facts(
        isDirectory: Bool = true,
        isLocalVolume: Bool = true,
        isWritable: Bool = true,
        availableCapacity: Int64? = 2_000,
        stagingSharesDestinationVolume: Bool = true,
        stagingAvailableCapacity: Int64? = 2_000,
        existingFilenames: Set<String> = []
    ) -> ImportDestinationPreflight.Facts {
        ImportDestinationPreflight.Facts(
            isDirectory: isDirectory,
            isLocalVolume: isLocalVolume,
            isWritable: isWritable,
            availableCapacity: availableCapacity,
            stagingSharesDestinationVolume: stagingSharesDestinationVolume,
            stagingAvailableCapacity: stagingAvailableCapacity,
            existingFilenames: existingFilenames
        )
    }
}
