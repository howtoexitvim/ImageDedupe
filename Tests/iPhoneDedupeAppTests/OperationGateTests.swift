import AppKit
import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

/// Phase 6 integration: the view model refuses overlapping device work, and its caches
/// stay bounded by memory as well as by count.
///
/// No real device operation runs here. `importSelected` and `deleteSelected` are only
/// reached in the *rejected* direction, where they return before touching the device.
@MainActor
final class OperationGateTests: XCTestCase {
    private func item(_ id: String) -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: DeviceMediaFile(
                id: id,
                name: "\(id).heic",
                kind: "heic",
                size: 1_000,
                timestamp: nil,
                width: nil,
                height: nil
            ),
            token: .fixture()
        )
    }

    private func viewModel() -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel()
        viewModel.allItems = ["a", "b", "c"].map { item($0) }
        viewModel.refreshVisibleOrder()
        return viewModel
    }

    // MARK: - Empty-selection protection still applies first

    func testImportWithNoSelectionIsRejectedWithoutClaimingTheGate() {
        let viewModel = viewModel()
        viewModel.importSelected()

        XCTAssertFalse(viewModel.isDeviceBusy, "a rejected import must not hold the gate")
        XCTAssertEqual(viewModel.status, "Select one or more items to import.")
    }

    func testFailedImportPreflightDoesNotClaimTheOperationGate() {
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unused-history-\(UUID().uuidString).json")
        let viewModel = MediaBrowserViewModel(
            operationResultStore: OperationResultStore(fileURL: historyURL),
            importPreflight: { _, _ in .blocked(.notWritable) }
        )
        let selectedItem = item("a")
        viewModel.allItems = [selectedItem]
        viewModel.refreshVisibleOrder()
        viewModel.toggleActionSelection(selectedItem)

        viewModel.importSelected()

        XCTAssertFalse(viewModel.isDeviceBusy)
        XCTAssertNil(viewModel.operationProgress)
        XCTAssertEqual(viewModel.status, "Import blocked: The destination folder is not writable.")
    }

    func testDeleteWithNoSelectionIsRejectedWithoutClaimingTheGate() {
        let viewModel = viewModel()
        viewModel.deleteSelected()

        XCTAssertFalse(viewModel.isDeviceBusy)
        XCTAssertEqual(viewModel.status, "Select one or more items to delete.")
    }

    func testDeleteConfirmationIsStillRequired() {
        let viewModel = viewModel()
        viewModel.toggleActionSelection(item("a"))
        viewModel.requestDeleteConfirmation()

        XCTAssertTrue(viewModel.isConfirmingDelete)
        XCTAssertFalse(viewModel.isDeviceBusy, "asking for confirmation must not start a delete")
        XCTAssertEqual(viewModel.allItems.count, 3)
    }

    func testDeleteConfirmationFreezesSelectionCountNamesAndBytes() throws {
        let viewModel = viewModel()
        viewModel.toggleActionSelection(item("a"))
        viewModel.requestDeleteConfirmation()
        let frozen = try XCTUnwrap(viewModel.pendingDeleteSnapshot)

        viewModel.toggleActionSelection(item("b"))

        XCTAssertEqual(frozen.items.map(\.filename), ["a.heic"])
        XCTAssertEqual(frozen.items.count, 1)
        XCTAssertEqual(frozen.totalBytes, 1_000)
        XCTAssertEqual(viewModel.pendingDeleteSnapshot, frozen)
    }

    // MARK: - Mutual exclusion

    /// Regression: import and delete previously had no admission guard at all, so a delete
    /// could begin while an import was still writing files.
    func testDeleteIsRejectedWhileAnotherOperationOwnsTheGate() {
        let viewModel = viewModel()
        viewModel.toggleActionSelection(item("a"))
        XCTAssertTrue(viewModel.beginOperationForTesting(.importing))

        viewModel.deleteSelected()

        XCTAssertEqual(viewModel.operationState.current, .importing, "the import still owns the gate")
        XCTAssertTrue(viewModel.status.contains("already in progress"))
        XCTAssertEqual(viewModel.allItems.count, 3, "nothing was deleted")
    }

    func testImportIsRejectedWhileAnotherOperationOwnsTheGate() {
        let viewModel = viewModel()
        viewModel.toggleActionSelection(item("a"))
        XCTAssertTrue(viewModel.beginOperationForTesting(.deleting))

        viewModel.importSelected()

        XCTAssertEqual(viewModel.operationState.current, .deleting)
        XCTAssertTrue(viewModel.status.contains("already in progress"))
    }

    func testScanIsRejectedWhileAnotherOperationOwnsTheGate() {
        let viewModel = viewModel()
        XCTAssertTrue(viewModel.beginOperationForTesting(.importing))

        viewModel.scan()

        XCTAssertEqual(viewModel.operationState.current, .importing)
        XCTAssertFalse(viewModel.isScanning)
    }

    func testIsScanningProjectsTheStateMachine() {
        let viewModel = viewModel()
        XCTAssertFalse(viewModel.isScanning)

        XCTAssertTrue(viewModel.beginOperationForTesting(.scanning))
        XCTAssertTrue(viewModel.isScanning)

        viewModel.finishOperationForTesting()
        XCTAssertFalse(viewModel.isScanning)
    }

    // MARK: - Session generation

    func testEachScanOpensANewSession() {
        let viewModel = viewModel()
        XCTAssertTrue(viewModel.beginOperationForTesting(.scanning))
        let first = viewModel.operationState.generation
        viewModel.finishOperationForTesting()

        XCTAssertTrue(viewModel.beginOperationForTesting(.scanning))
        XCTAssertNotEqual(viewModel.operationState.generation, first)
        XCTAssertFalse(viewModel.operationState.isCurrent(generation: first))
    }

    func testImportDoesNotInvalidateCachedWork() {
        let viewModel = viewModel()
        XCTAssertTrue(viewModel.beginOperationForTesting(.scanning))
        let session = viewModel.operationState.generation
        viewModel.finishOperationForTesting()

        XCTAssertTrue(viewModel.beginOperationForTesting(.importing))
        viewModel.finishOperationForTesting()

        XCTAssertTrue(
            viewModel.operationState.isCurrent(generation: session),
            "an import must not throw away thumbnails from the current scan"
        )
    }

    // MARK: - Thumbnail cache cost

    func testThumbnailCostGrowsWithPixelCount() {
        let small = NSImage(size: NSSize(width: 10, height: 10))
        small.addRepresentation(bitmap(width: 10, height: 10))
        let large = NSImage(size: NSSize(width: 200, height: 200))
        large.addRepresentation(bitmap(width: 200, height: 200))

        XCTAssertGreaterThan(
            MediaBrowserViewModel.thumbnailCost(of: large),
            MediaBrowserViewModel.thumbnailCost(of: small)
        )
    }

    func testThumbnailCostIsZeroForAnImageWithNoRepresentation() {
        XCTAssertEqual(MediaBrowserViewModel.thumbnailCost(of: NSImage(size: .zero)), 0)
    }

    func testThumbnailCostUsesFourBytesPerPixel() {
        let image = NSImage(size: NSSize(width: 100, height: 50))
        image.addRepresentation(bitmap(width: 100, height: 50))

        XCTAssertEqual(MediaBrowserViewModel.thumbnailCost(of: image), 100 * 50 * 4)
    }

    private func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
    }
}
