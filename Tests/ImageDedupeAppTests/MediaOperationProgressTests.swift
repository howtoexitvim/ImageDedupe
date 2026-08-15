import DeviceMediaKit
import XCTest
@testable import ImageDedupeApp

final class MediaOperationProgressTests: XCTestCase {
    func testImportProgressIncludesTheCurrentFilename() {
        var progress = MediaOperationProgress(kind: .importing, totalItems: 4)

        progress.apply(DeviceBatchProgress(
            completedItems: 1,
            totalItems: 4,
            currentFilename: "IMG_0002.HEIC",
            fractionCompleted: 0.375
        ))

        XCTAssertEqual(progress.completedItems, 1)
        XCTAssertEqual(progress.currentFilename, "IMG_0002.HEIC")
        XCTAssertEqual(progress.fractionCompleted, 0.375)
        XCTAssertEqual(progress.detail, "Importing IMG_0002.HEIC — 1 of 4")
    }

    func testDeleteProgressDoesNotInventACurrentFilename() {
        var progress = MediaOperationProgress(kind: .deleting, totalItems: 4)

        progress.apply(DeviceBatchProgress(
            completedItems: 2,
            totalItems: 4,
            currentFilename: nil,
            fractionCompleted: 0.5
        ))

        XCTAssertNil(progress.currentFilename)
        XCTAssertEqual(progress.detail, "Deleting — 2 of 4")
    }

    func testRequestCancellationIsIdempotentAndDisablesCancel() {
        var progress = MediaOperationProgress(kind: .importing, totalItems: 2)

        XCTAssertTrue(progress.canCancel)
        XCTAssertTrue(progress.requestCancellation())
        XCTAssertTrue(progress.isCanceling)
        XCTAssertEqual(progress.detail, "Canceling import…")
        XCTAssertFalse(progress.canCancel)
        XCTAssertFalse(progress.requestCancellation())
    }

    func testApplyingOutOfRangeProgressIsClamped() {
        var progress = MediaOperationProgress(kind: .deleting, totalItems: 2)

        progress.apply(DeviceBatchProgress(
            completedItems: 9,
            totalItems: 2,
            currentFilename: nil,
            fractionCompleted: 2
        ))

        XCTAssertEqual(progress.completedItems, 2)
        XCTAssertEqual(progress.fractionCompleted, 1)
    }
}
