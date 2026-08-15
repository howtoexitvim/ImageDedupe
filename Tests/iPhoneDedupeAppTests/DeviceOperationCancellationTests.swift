import DeviceMediaKit
import Foundation
import XCTest

@MainActor
final class DeviceOperationCancellationTests: XCTestCase {
    func testCancelIsIdempotent() {
        let cancellation = DeviceOperationCancellation()

        XCTAssertFalse(cancellation.isCancellationRequested)
        XCTAssertTrue(cancellation.cancel())
        XCTAssertTrue(cancellation.isCancellationRequested)
        XCTAssertFalse(cancellation.cancel())
    }

    func testCancelForwardsToTheBoundFoundationProgress() {
        let cancellation = DeviceOperationCancellation()
        let progress = Progress(totalUnitCount: 10)
        cancellation.bind(progress)

        _ = cancellation.cancel()

        XCTAssertTrue(progress.isCancelled)
    }

    func testBindingAfterCancellationCancelsProgressImmediately() {
        let cancellation = DeviceOperationCancellation()
        _ = cancellation.cancel()
        let progress = Progress(totalUnitCount: 10)

        cancellation.bind(progress)

        XCTAssertTrue(progress.isCancelled)
    }

    func testBatchProgressClampsCountsAndFraction() {
        let progress = DeviceBatchProgress(
            completedItems: 8,
            totalItems: 3,
            currentFilename: "IMG_0003.HEIC",
            fractionCompleted: 1.4
        )

        XCTAssertEqual(progress.completedItems, 3)
        XCTAssertEqual(progress.totalItems, 3)
        XCTAssertEqual(progress.currentFilename, "IMG_0003.HEIC")
        XCTAssertEqual(progress.fractionCompleted, 1)
    }
}
