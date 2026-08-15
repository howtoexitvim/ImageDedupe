import XCTest
@testable import ImageDedupeApp

/// Phase 6: thumbnail and metadata requests are bounded and cancellable.
///
/// Scrolling a 4,000-item catalog previously enqueued an unbounded, uncancellable pile of
/// per-item device requests. Items scrolled past long ago still had work queued ahead of
/// what the user is actually looking at.
@MainActor
final class MediaRequestQueueTests: XCTestCase {
    func testQueueStartsEmpty() {
        let queue = MediaRequestQueue(maxConcurrent: 4)
        XCTAssertEqual(queue.activeCount, 0)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testRequestsUpToTheLimitStartImmediately() {
        let queue = MediaRequestQueue(maxConcurrent: 2)
        XCTAssertTrue(queue.beginIfAllowed("a"))
        XCTAssertTrue(queue.beginIfAllowed("b"))

        XCTAssertEqual(queue.activeCount, 2)
    }

    /// The bound is the point: a burst of scrolling must not put hundreds of requests on
    /// the device at once.
    func testRequestsBeyondTheLimitAreRefused() {
        let queue = MediaRequestQueue(maxConcurrent: 2)
        _ = queue.beginIfAllowed("a")
        _ = queue.beginIfAllowed("b")

        XCTAssertFalse(queue.beginIfAllowed("c"))
        XCTAssertEqual(queue.activeCount, 2)
    }

    func testFinishingFreesASlot() {
        let queue = MediaRequestQueue(maxConcurrent: 1)
        _ = queue.beginIfAllowed("a")
        XCTAssertFalse(queue.beginIfAllowed("b"))

        queue.finish("a")

        XCTAssertTrue(queue.beginIfAllowed("b"))
    }

    func testTheSameIDIsNotRequestedTwice() {
        let queue = MediaRequestQueue(maxConcurrent: 4)
        XCTAssertTrue(queue.beginIfAllowed("a"))
        XCTAssertFalse(queue.beginIfAllowed("a"), "already in flight")
        XCTAssertEqual(queue.activeCount, 1)
    }

    func testFinishingAnUnknownIDIsHarmless() {
        let queue = MediaRequestQueue(maxConcurrent: 2)
        queue.finish("never-started")
        XCTAssertEqual(queue.activeCount, 0)
    }

    // MARK: - Cancellation

    func testCancellingAnInFlightRequestFreesItsSlot() {
        let queue = MediaRequestQueue(maxConcurrent: 1)
        _ = queue.beginIfAllowed("a")

        queue.cancel("a")

        XCTAssertEqual(queue.activeCount, 0)
        XCTAssertTrue(queue.beginIfAllowed("b"))
    }

    /// A cancelled request's result must be discarded even if it was already in flight.
    func testACancelledRequestIsNoLongerCurrent() {
        let queue = MediaRequestQueue(maxConcurrent: 2)
        _ = queue.beginIfAllowed("a")
        XCTAssertTrue(queue.isActive("a"))

        queue.cancel("a")

        XCTAssertFalse(queue.isActive("a"))
    }

    func testCancelAllClearsEverything() {
        let queue = MediaRequestQueue(maxConcurrent: 4)
        _ = queue.beginIfAllowed("a")
        _ = queue.beginIfAllowed("b")
        _ = queue.beginIfAllowed("c")

        queue.cancelAll()

        XCTAssertEqual(queue.activeCount, 0)
        XCTAssertTrue(queue.beginIfAllowed("a"), "IDs can be requested again after a reset")
    }

    /// Scrolling away from an item should abandon its request so the visible rows get the
    /// device's attention instead.
    func testCancellingRequestsOutsideAKeepSet() {
        let queue = MediaRequestQueue(maxConcurrent: 8)
        for id in ["a", "b", "c", "d"] {
            _ = queue.beginIfAllowed(id)
        }

        queue.cancelRequests(notIn: ["c", "d"])

        XCTAssertFalse(queue.isActive("a"))
        XCTAssertFalse(queue.isActive("b"))
        XCTAssertTrue(queue.isActive("c"))
        XCTAssertTrue(queue.isActive("d"))
        XCTAssertEqual(queue.activeCount, 2)
    }

    func testKeepSetCancellationFreesSlotsForNewWork() {
        let queue = MediaRequestQueue(maxConcurrent: 2)
        _ = queue.beginIfAllowed("offscreen-1")
        _ = queue.beginIfAllowed("offscreen-2")
        XCTAssertFalse(queue.beginIfAllowed("visible"))

        queue.cancelRequests(notIn: ["visible"])

        XCTAssertTrue(queue.beginIfAllowed("visible"))
    }

    // MARK: - Bound sanity

    func testConcurrencyLimitIsPositiveEvenIfMisconfigured() {
        let queue = MediaRequestQueue(maxConcurrent: 0)
        XCTAssertTrue(queue.beginIfAllowed("a"), "a zero limit would deadlock the queue")
    }
}
