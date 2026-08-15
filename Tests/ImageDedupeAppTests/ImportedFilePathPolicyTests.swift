import Foundation
import XCTest
@testable import DeviceMediaKit

final class ImportedFilePathPolicyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-dedupe-path-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testAcceptsAnExistingRegularFileInsideTheDestination() throws {
        let fileURL = directory.appendingPathComponent("IMG_0001.HEIC")
        try Data("photo".utf8).write(to: fileURL)

        let validated = try ImportedFilePathPolicy.validateCompletedDownload(
            callbackFilename: "IMG_0001.HEIC",
            destination: directory
        )

        XCTAssertEqual(validated, fileURL.resolvingSymlinksInPath().standardizedFileURL)
    }

    func testRejectsUnsafeCallbackNames() throws {
        let unsafeNames = [
            "",
            ".",
            "..",
            "/tmp/escaped.heic",
            "nested/escaped.heic",
            "nested\\escaped.heic"
        ]

        for filename in unsafeNames {
            XCTAssertThrowsError(
                try ImportedFilePathPolicy.validateCompletedDownload(
                    callbackFilename: filename,
                    destination: directory
                ),
                "expected \(filename.debugDescription) to be rejected"
            )
        }
    }

    func testRejectsAMissingCallbackFile() {
        XCTAssertThrowsError(
            try ImportedFilePathPolicy.validateCompletedDownload(
                callbackFilename: "missing.heic",
                destination: directory
            )
        )
    }

    func testRejectsASymbolicLinkEvenWhenItsTargetIsInsideTheDestination() throws {
        let target = directory.appendingPathComponent("target.heic")
        let link = directory.appendingPathComponent("IMG_0001.HEIC")
        try Data("photo".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(
            try ImportedFilePathPolicy.validateCompletedDownload(
                callbackFilename: "IMG_0001.HEIC",
                destination: directory
            )
        )
    }

    func testRejectsASymbolicLinkThatEscapesTheDestination() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-dedupe-outside-\(UUID().uuidString).heic")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("IMG_0001.HEIC"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try ImportedFilePathPolicy.validateCompletedDownload(
                callbackFilename: "IMG_0001.HEIC",
                destination: directory
            )
        )
    }

    func testDestinationIdentityAcceptsTheOriginalDirectory() throws {
        let identity = try ImportDestinationIdentity.capture(destination: directory)

        XCTAssertNoThrow(try identity.validate(destination: directory))
    }

    func testDestinationIdentityRejectsAReplacementAtTheSamePath() throws {
        let destination = directory.appendingPathComponent("destination", isDirectory: true)
        let original = directory.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let identity = try ImportDestinationIdentity.capture(destination: destination)

        try FileManager.default.moveItem(at: destination, to: original)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        XCTAssertThrowsError(try identity.validate(destination: destination))
    }

    func testDestinationIdentityRejectsASwappedSymlinkTarget() throws {
        let firstTarget = directory.appendingPathComponent("first", isDirectory: true)
        let secondTarget = directory.appendingPathComponent("second", isDirectory: true)
        let destination = directory.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: firstTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: firstTarget)
        let identity = try ImportDestinationIdentity.capture(destination: destination)

        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: secondTarget)

        XCTAssertThrowsError(try identity.validate(destination: destination))
    }
}
