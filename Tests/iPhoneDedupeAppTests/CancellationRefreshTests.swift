import DeduperCore
import DeviceMediaKit
import Foundation
import XCTest

@testable import iPhoneDedupeApp

/// After a canceled operation the app's view of the device is partly stale by construction:
/// a cancel lands mid-batch, so some files are already deleted or already downloaded and
/// the rest are not. Reported on 2026-08-15 for both Delete Cancel and Download Cancel —
/// the user had to press Scan themselves to find out what had actually happened.
///
/// These cover the state the badges are allowed to claim. The rescan itself needs a device
/// and is verified by hand.
@MainActor
final class CancellationRefreshTests: XCTestCase {
    private var destination: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        destination = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cancel-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let destination, FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try super.tearDownWithError()
    }

    /// The green tick means "this file is on your disk". It must therefore be keyed on the
    /// file existing, not on a summary that a cancel may have cut short: a canceled batch
    /// settles while a commit is still in flight, and an item reported successful could end
    /// up never reaching the destination.
    func testTheDownloadedBadgeIsDroppedWhenTheFileIsNotOnDisk() {
        let viewModel = MediaBrowserViewModel()
        let present = destination.appendingPathComponent("PRESENT.HEIC")
        FileManager.default.createFile(atPath: present.path, contents: Data([0x01]))
        let absent = destination.appendingPathComponent("ABSENT.HEIC")

        viewModel.recordSuccessfulDownload(itemID: "present", fileURL: present)
        viewModel.recordSuccessfulDownload(itemID: "absent", fileURL: absent)
        XCTAssertEqual(viewModel.importedItemIDs, ["present", "absent"])

        viewModel.reconcileImportedDownloads()

        XCTAssertEqual(
            viewModel.importedItemIDs,
            ["present"],
            "A badge must not survive for a file that never reached the destination."
        )
    }

    /// The badge and the import preflight must agree. They disagreed after a rescan cleared
    /// the badges while the files were still on disk: the user pressed Download again and
    /// was told "Import blocked", because the preflight could see what the badge no longer
    /// showed.
    func testABadgeSurvivesWhileItsFileRemainsOnDisk() {
        let viewModel = MediaBrowserViewModel()
        let fileURL = destination.appendingPathComponent("KEPT.HEIC")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x01]))

        viewModel.recordSuccessfulDownload(itemID: "kept", fileURL: fileURL)
        viewModel.reconcileImportedDownloads()

        XCTAssertEqual(viewModel.importedItemIDs, ["kept"])
    }

    /// Deleting the file behind a badge, as the user may do in Finder, retires the badge on
    /// the next reconcile so Download becomes available again.
    func testRemovingTheFileRetiresTheBadge() throws {
        let viewModel = MediaBrowserViewModel()
        let fileURL = destination.appendingPathComponent("GONE.HEIC")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x01]))
        viewModel.recordSuccessfulDownload(itemID: "gone", fileURL: fileURL)

        try FileManager.default.removeItem(at: fileURL)
        viewModel.reconcileImportedDownloads()

        XCTAssertTrue(viewModel.importedItemIDs.isEmpty)
    }
}
