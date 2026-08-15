import Foundation
import XCTest

@testable import DeviceMediaKit

/// The device helper stages downloads into a directory the app nominates, so that path
/// crosses a process boundary. It is an input from outside the process and must be
/// validated, not trusted: if an unexpected path were adopted, downloaded bytes would land
/// somewhere the user never chose.
final class StagingAdoptionTests: XCTestCase {
    private var root: URL!
    private var manager: ImportStagingManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("staging-adoption-\(UUID().uuidString)", isDirectory: true)
        manager = ImportStagingManager(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    func testAdoptsASessionThisManagerCreated() throws {
        let created = try manager.createSession()
        let adopted = try manager.adoptSession(at: created.directory)

        XCTAssertEqual(adopted.directory, created.directory)
        XCTAssertEqual(adopted.markerURL, created.markerURL)
        XCTAssertEqual(
            created.markerURL.lastPathComponent,
            ".image-dedupe-staging",
            "New sessions must stop creating artifacts under the former product name."
        )
    }

    /// An upgrade can leave an in-flight directory created by the former app name. The
    /// helper must still be able to adopt it so the app can finish or clean the operation.
    func testAdoptsALegacyMarkedSession() throws {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyMarker = directory.appendingPathComponent(".iphone-dedupe-staging")
        XCTAssertTrue(FileManager.default.createFile(atPath: legacyMarker.path, contents: Data()))

        let adopted = try manager.adoptSession(at: directory)

        XCTAssertEqual(adopted.directory, directory)
        XCTAssertEqual(adopted.markerURL, legacyMarker)
    }

    /// The marker is what distinguishes a staging directory from an arbitrary one.
    func testRefusesADirectoryWithoutTheStagingMarker() throws {
        let unmarked = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: true)

        XCTAssertThrowsError(try manager.adoptSession(at: unmarked)) { error in
            XCTAssertTrue("\(error)".contains("marker"), "Unexpected error: \(error)")
        }
    }

    /// A path outside the staging root is the case that would redirect downloaded bytes.
    func testRefusesADirectoryOutsideTheStagingRoot() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        XCTAssertThrowsError(try manager.adoptSession(at: outside)) { error in
            XCTAssertTrue("\(error)".contains("outside"), "Unexpected error: \(error)")
        }
    }

    /// `..` must not be a way back out of the root.
    func testRefusesATraversalPathThatEscapesTheRoot() throws {
        let created = try manager.createSession()
        let traversal = created.directory
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)

        XCTAssertThrowsError(try manager.adoptSession(at: traversal))
    }

    /// A symlink inside the root could otherwise point anywhere at all.
    func testRefusesASymbolicLinkStandingInForASession() throws {
        let created = try manager.createSession()
        let link = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: created.directory)

        XCTAssertThrowsError(try manager.adoptSession(at: link)) { error in
            XCTAssertTrue("\(error)".contains("not a directory"), "Unexpected error: \(error)")
        }
    }

    /// A nested directory is not a session even if it carries a marker: sessions are
    /// immediate children of the root, and accepting deeper paths would widen the surface.
    func testRefusesADirectoryNestedBelowASession() throws {
        let created = try manager.createSession()
        let nested = created.directory.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: nested.appendingPathComponent(ImportStagingManager.markerFilename).path,
            contents: Data()
        )

        XCTAssertThrowsError(try manager.adoptSession(at: nested))
    }
}
