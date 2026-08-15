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

    func testExistingFilenameCollisionIsBlocked() {
        let result = ImportDestinationPreflight.evaluate(
            items: items,
            facts: facts(existingFilenames: ["IMG_0002.MOV"])
        )

        XCTAssertEqual(result, .blocked(.filenameCollisions(["IMG_0002.MOV"])))
    }

    func testDuplicateRequestedFilenameIsAlsoACollision() {
        let duplicateItems = [
            ImportDestinationPreflight.Item(filename: "same.heic", size: 10),
            ImportDestinationPreflight.Item(filename: "SAME.HEIC", size: 10)
        ]

        let result = ImportDestinationPreflight.evaluate(
            items: duplicateItems,
            facts: facts()
        )

        XCTAssertEqual(result, .blocked(.filenameCollisions(["SAME.HEIC", "same.heic"])))
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

    func testInspectDetectsARealExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("existing".utf8).write(to: directory.appendingPathComponent("IMG_0001.HEIC"))

        let result = ImportDestinationPreflight.inspect(
            destination: directory,
            items: [ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 1)]
        )

        XCTAssertEqual(result, .blocked(.filenameCollisions(["IMG_0001.HEIC"])))
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
