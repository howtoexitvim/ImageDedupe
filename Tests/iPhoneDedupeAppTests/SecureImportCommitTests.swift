@testable import DeviceMediaKit
import Foundation
import XCTest

final class SecureImportCommitTests: XCTestCase {
    func testStagingSessionIsPrivateMarkedAndCleanupIsScoped() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ImportStagingManager(rootDirectory: root)

        let session = try manager.createSession()
        let attributes = try FileManager.default.attributesOfItem(atPath: session.directory.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue

        XCTAssertEqual(mode, 0o700)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.markerURL.path))

        try manager.cleanup(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directory.path))
    }

    func testStagingCleanupRefusesUnmarkedDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ImportStagingManager(rootDirectory: root)
        let unmarked = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: false)

        XCTAssertThrowsError(try manager.cleanupDirectory(unmarked)) { error in
            XCTAssertEqual(error as? ImportStagingError, .missingMarker)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmarked.path))
    }

    func testStaleCleanupRemovesOnlyMarkedImmediateChildDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ImportStagingManager(rootDirectory: root)
        let staleSession = try manager.createSession()
        let activeSession = try manager.createSession()
        let cutoff = Date(timeIntervalSince1970: 10_000)
        try Data(String(Int32.max).utf8).write(to: staleSession.markerURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: staleSession.markerURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: activeSession.markerURL.path
        )
        let unmarked = root.appendingPathComponent("user-owned", isDirectory: true)
        try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: false)

        try manager.cleanupStaleSessions(olderThan: cutoff)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleSession.directory.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: activeSession.directory.path),
            "an old marker owned by a live app process is not stale"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmarked.path))
    }

    func testCapacityCheckRequiresEnoughSpaceForTheWholeStagedFile() {
        XCTAssertTrue(DestinationCommitter.hasSufficientCapacity(requiredBytes: 10, availableBytes: 10))
        XCTAssertFalse(DestinationCommitter.hasSufficientCapacity(requiredBytes: 11, availableBytes: 10))
        XCTAssertFalse(DestinationCommitter.hasSufficientCapacity(requiredBytes: 1, availableBytes: -1))
    }

    func testCommitCopiesThenAtomicallyPublishesWithoutOverwrite() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let staged = stagingRoot.appendingPathComponent("download.tmp")
        try Data("new bytes".utf8).write(to: staged)
        let identity = try ImportDestinationIdentity.capture(destination: destination)
        let stagingIdentity = try ImportDestinationIdentity.capture(destination: stagingRoot)
        let stagedIdentity = try StagedFileIdentity.capture(
            filename: staged.lastPathComponent,
            stagingDirectory: stagingRoot,
            stagingIdentity: stagingIdentity
        )

        let output = try DestinationCommitter.commit(
            stagedFilename: staged.lastPathComponent,
            stagingDirectory: stagingRoot,
            stagingIdentity: stagingIdentity,
            stagedIdentity: stagedIdentity,
            filename: "IMG_0001.HEIC",
            destination: destination,
            destinationIdentity: identity
        )

        XCTAssertEqual(try Data(contentsOf: output), Data("new bytes".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCommitNeverOverwritesExistingDestinationFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staged")
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("new".utf8).write(to: staging)
        let existing = destination.appendingPathComponent("IMG_0001.HEIC")
        try Data("old".utf8).write(to: existing)
        let identity = try ImportDestinationIdentity.capture(destination: destination)
        let stagingDirectory = staging.deletingLastPathComponent()
        let stagingIdentity = try ImportDestinationIdentity.capture(destination: stagingDirectory)
        let stagedIdentity = try StagedFileIdentity.capture(
            filename: staging.lastPathComponent,
            stagingDirectory: stagingDirectory,
            stagingIdentity: stagingIdentity
        )

        XCTAssertThrowsError(try DestinationCommitter.commit(
            stagedFilename: staging.lastPathComponent,
            stagingDirectory: stagingDirectory,
            stagingIdentity: stagingIdentity,
            stagedIdentity: stagedIdentity,
            filename: existing.lastPathComponent,
            destination: destination,
            destinationIdentity: identity
        )) { error in
            XCTAssertEqual(error as? DestinationCommitError, .collision)
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data("old".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
    }

    func testCommitRejectsReplacementStagingDirectoryAtTheSamePath() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let movedStaging = root.appendingPathComponent("moved-staging", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: staging.appendingPathComponent("download.tmp"))
        let stagingIdentity = try ImportDestinationIdentity.capture(destination: staging)
        let stagedIdentity = try StagedFileIdentity.capture(
            filename: "download.tmp",
            stagingDirectory: staging,
            stagingIdentity: stagingIdentity
        )
        let destinationIdentity = try ImportDestinationIdentity.capture(destination: destination)
        try FileManager.default.moveItem(at: staging, to: movedStaging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: staging.appendingPathComponent("download.tmp"))

        XCTAssertThrowsError(try DestinationCommitter.commit(
            stagedFilename: "download.tmp",
            stagingDirectory: staging,
            stagingIdentity: stagingIdentity,
            stagedIdentity: stagedIdentity,
            filename: "IMG_0001.HEIC",
            destination: destination,
            destinationIdentity: destinationIdentity
        )) { error in
            XCTAssertEqual(error as? DestinationCommitError, .stagingChanged)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("IMG_0001.HEIC").path))
    }

    func testCommitRejectsSameNameStagedFileReplacementAfterIdentityCapture() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let staged = staging.appendingPathComponent("download.tmp")
        try Data("original".utf8).write(to: staged)
        let stagingIdentity = try ImportDestinationIdentity.capture(destination: staging)
        let stagedIdentity = try StagedFileIdentity.capture(
            filename: staged.lastPathComponent,
            stagingDirectory: staging,
            stagingIdentity: stagingIdentity
        )
        let destinationIdentity = try ImportDestinationIdentity.capture(destination: destination)
        try FileManager.default.removeItem(at: staged)
        try Data("replacement".utf8).write(to: staged)

        XCTAssertThrowsError(try DestinationCommitter.commit(
            stagedFilename: staged.lastPathComponent,
            stagingDirectory: staging,
            stagingIdentity: stagingIdentity,
            stagedIdentity: stagedIdentity,
            filename: "IMG_0001.HEIC",
            destination: destination,
            destinationIdentity: destinationIdentity
        )) { error in
            XCTAssertEqual(error as? DestinationCommitError, .stagedFileInvalid)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("IMG_0001.HEIC").path))
    }

    func testCommitRejectsSymlinkDestinationAndUnsafeFilename() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realDestination = root.appendingPathComponent("real", isDirectory: true)
        let linkedDestination = root.appendingPathComponent("linked", isDirectory: true)
        let staged = root.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: realDestination, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedDestination, withDestinationURL: realDestination)
        try Data("bytes".utf8).write(to: staged)
        let identity = try ImportDestinationIdentity.capture(destination: realDestination)
        let stagingDirectory = staged.deletingLastPathComponent()
        let stagingIdentity = try ImportDestinationIdentity.capture(destination: stagingDirectory)
        let stagedIdentity = try StagedFileIdentity.capture(
            filename: staged.lastPathComponent,
            stagingDirectory: stagingDirectory,
            stagingIdentity: stagingIdentity
        )

        XCTAssertThrowsError(try DestinationCommitter.commit(
            stagedFilename: staged.lastPathComponent,
            stagingDirectory: stagingDirectory,
            stagingIdentity: stagingIdentity,
            stagedIdentity: stagedIdentity,
            filename: "IMG.HEIC",
            destination: linkedDestination,
            destinationIdentity: identity
        ))
        XCTAssertThrowsError(try DestinationCommitter.commit(
            stagedFilename: staged.lastPathComponent,
            stagingDirectory: stagingDirectory,
            stagingIdentity: stagingIdentity,
            stagedIdentity: stagedIdentity,
            filename: "../escape.HEIC",
            destination: realDestination,
            destinationIdentity: identity
        )) { error in
            XCTAssertEqual(error as? DestinationCommitError, .unsafeFilename)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-secure-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
