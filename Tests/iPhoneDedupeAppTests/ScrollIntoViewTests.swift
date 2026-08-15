import AppKit
import XCTest
@testable import iPhoneDedupeApp

/// Keyboard scroll-into-view and drag edge auto-scroll geometry.
///
/// Both renderers share this maths so List and Grid feel identical. Everything here is a
/// pure function of rectangles, so it is testable without a window or a run loop.
final class ScrollIntoViewTests: XCTestCase {
    // MARK: - Keyboard scroll into view

    private let viewport = NSRect(x: 0, y: 100, width: 800, height: 400)

    func testFullyVisibleItemDoesNotScroll() {
        let target = NSRect(x: 0, y: 200, width: 800, height: 40)
        XCTAssertNil(MediaScrollGeometry.originToRevealItem(target, in: viewport, padding: 0))
    }

    /// Finder keeps a little context around the focused item rather than parking it flush
    /// against the edge. `scrollRowToVisible` alone scrolls the minimum amount, which is
    /// what made keyboard navigation feel like it "wasn't scrolling".
    func testItemFlushWithTheTopEdgeStillScrollsForPadding() {
        let target = NSRect(x: 0, y: 100, width: 800, height: 40)
        let origin = MediaScrollGeometry.originToRevealItem(target, in: viewport, padding: 24)

        XCTAssertNotNil(origin)
        XCTAssertEqual(origin, 76)
    }

    func testItemAboveTheViewportScrollsUp() {
        let target = NSRect(x: 0, y: 20, width: 800, height: 40)
        let origin = MediaScrollGeometry.originToRevealItem(target, in: viewport, padding: 0)

        XCTAssertEqual(origin, 20)
    }

    func testItemBelowTheViewportScrollsDown() {
        let target = NSRect(x: 0, y: 600, width: 800, height: 40)
        let origin = MediaScrollGeometry.originToRevealItem(target, in: viewport, padding: 0)

        // Bottom of the item (640) minus viewport height (400).
        XCTAssertEqual(origin, 240)
    }

    func testScrollingDownKeepsPaddingBelowTheItem() {
        let target = NSRect(x: 0, y: 600, width: 800, height: 40)
        let origin = MediaScrollGeometry.originToRevealItem(target, in: viewport, padding: 24)

        XCTAssertEqual(origin, 264)
    }

    func testOriginNeverGoesNegative() {
        let target = NSRect(x: 0, y: 0, width: 800, height: 40)
        let smallViewport = NSRect(x: 0, y: 0, width: 800, height: 400)
        let origin = MediaScrollGeometry.originToRevealItem(target, in: smallViewport, padding: 24)

        XCTAssertNil(origin, "an item already at the very top has nowhere to scroll")
    }

    func testItemTallerThanTheViewportAlignsToItsTop() {
        let target = NSRect(x: 0, y: 50, width: 800, height: 900)
        let origin = MediaScrollGeometry.originToRevealItem(target, in: viewport, padding: 0)

        XCTAssertEqual(origin, 50)
    }

    // MARK: - Drag edge auto-scroll

    func testAutoScrollIsIdleInTheMiddle() {
        XCTAssertEqual(MediaTableMetrics.autoScrollVelocity(pointerY: 200, viewportHeight: 400), 0)
    }

    func testAutoScrollGoesUpNearTheTopEdge() {
        XCTAssertLessThan(MediaTableMetrics.autoScrollVelocity(pointerY: 5, viewportHeight: 400), 0)
    }

    func testAutoScrollGoesDownNearTheBottomEdge() {
        XCTAssertGreaterThan(MediaTableMetrics.autoScrollVelocity(pointerY: 395, viewportHeight: 400), 0)
    }

    /// The same curve drives both renderers, so a drag feels identical in List and Grid.
    func testAutoScrollAcceleratesTowardTheEdge() {
        let near = abs(MediaTableMetrics.autoScrollVelocity(pointerY: 1, viewportHeight: 400))
        let far = abs(MediaTableMetrics.autoScrollVelocity(pointerY: 20, viewportHeight: 400))
        XCTAssertGreaterThan(near, far)
    }

    func testAutoScrollIsClampedToTheMaximumVelocity() {
        let beyondEdge = abs(MediaTableMetrics.autoScrollVelocity(pointerY: -500, viewportHeight: 400))
        XCTAssertLessThanOrEqual(beyondEdge, MediaTableMetrics.maximumAutoScrollVelocity)
    }

    func testTinyViewportDoesNotAutoScroll() {
        // A viewport smaller than both margins would otherwise scroll in both directions
        // at once.
        XCTAssertEqual(MediaTableMetrics.autoScrollVelocity(pointerY: 10, viewportHeight: 30), 0)
    }

    // MARK: - How far a drag may stray

    func testDragInsideTheViewportExtends() {
        XCTAssertTrue(
            MediaScrollGeometry.dragShouldExtend(at: NSPoint(x: 400, y: 300), viewport: viewport)
        )
    }

    /// Finder keeps auto-scrolling while the pointer rests far above or below the list,
    /// including off the window. Unlimited vertical overshoot is the whole point of edge
    /// auto-scroll, so these must keep extending.
    func testDragFarBelowTheViewportStillExtends() {
        XCTAssertTrue(
            MediaScrollGeometry.dragShouldExtend(at: NSPoint(x: 400, y: -5_000), viewport: viewport)
        )
    }

    func testDragFarAboveTheViewportStillExtends() {
        XCTAssertTrue(
            MediaScrollGeometry.dragShouldExtend(at: NSPoint(x: 400, y: 9_000), viewport: viewport)
        )
    }

    /// Regression: a pointer dragged sideways out of the app kept selecting items the user
    /// could not see.
    func testDragFarToTheRightStopsExtending() {
        XCTAssertFalse(
            MediaScrollGeometry.dragShouldExtend(at: NSPoint(x: 3_000, y: 300), viewport: viewport)
        )
    }

    func testDragFarToTheLeftStopsExtending() {
        XCTAssertFalse(
            MediaScrollGeometry.dragShouldExtend(at: NSPoint(x: -3_000, y: 300), viewport: viewport)
        )
    }

    /// Ordinary sloppy dragging just past the side of the list keeps working.
    func testSlightHorizontalOvershootStillExtends() {
        XCTAssertTrue(
            MediaScrollGeometry.dragShouldExtend(
                at: NSPoint(x: viewport.maxX + 40, y: 300),
                viewport: viewport
            )
        )
    }

    // MARK: - Auto-scroll past the edge

    /// Regression: the velocity clamped the pointer back into the viewport, so a drag well
    /// past an edge computed a smaller depth. Scrolling stalled or ran backwards.
    func testDragFarAboveTheTopScrollsUpAtFullSpeed() {
        let velocity = MediaTableMetrics.autoScrollVelocity(pointerY: -800, viewportHeight: 400)
        XCTAssertEqual(velocity, -MediaTableMetrics.maximumAutoScrollVelocity)
    }

    func testDragFarBelowTheBottomScrollsDownAtFullSpeed() {
        let velocity = MediaTableMetrics.autoScrollVelocity(pointerY: 1_200, viewportHeight: 400)
        XCTAssertEqual(velocity, MediaTableMetrics.maximumAutoScrollVelocity)
    }

    /// Direction must never flip as the pointer travels further past an edge.
    func testVelocityNeverReversesAsThePointerTravelsFurtherOut() {
        for y in stride(from: 0.0, through: -2_000.0, by: -50.0) {
            XCTAssertLessThan(
                MediaTableMetrics.autoScrollVelocity(pointerY: y, viewportHeight: 400),
                0,
                "should still scroll up at pointerY=\(y)"
            )
        }
        for y in stride(from: 400.0, through: 2_400.0, by: 50.0) {
            XCTAssertGreaterThan(
                MediaTableMetrics.autoScrollVelocity(pointerY: y, viewportHeight: 400),
                0,
                "should still scroll down at pointerY=\(y)"
            )
        }
    }

    /// The trigger band is wide enough to find without precision aiming.
    func testEdgeBandIsGenerousEnoughToHit() {
        XCTAssertGreaterThanOrEqual(MediaTableMetrics.autoScrollMargin, 40)
    }

    // MARK: - Marquee rectangle

    func testMarqueeRectNormalizesADragUpAndLeft() {
        let rect = MediaScrollGeometry.marqueeRect(
            from: NSPoint(x: 300, y: 400),
            to: NSPoint(x: 100, y: 200)
        )
        XCTAssertEqual(rect, NSRect(x: 100, y: 200, width: 200, height: 200))
    }

    func testMarqueeRectNormalizesADragDownAndRight() {
        let rect = MediaScrollGeometry.marqueeRect(
            from: NSPoint(x: 100, y: 200),
            to: NSPoint(x: 300, y: 400)
        )
        XCTAssertEqual(rect, NSRect(x: 100, y: 200, width: 200, height: 200))
    }

    func testAZeroLengthDragProducesAnEmptyRect() {
        let rect = MediaScrollGeometry.marqueeRect(
            from: NSPoint(x: 100, y: 100),
            to: NSPoint(x: 100, y: 100)
        )
        XCTAssertTrue(rect.isEmpty)
    }

    /// The marquee anchor lives in document coordinates so it stays pinned to content
    /// while the view auto-scrolls underneath it.
    func testMarqueeGrowsAsTheDocumentScrollsUnderIt() {
        let anchor = NSPoint(x: 100, y: 100)
        let beforeScroll = MediaScrollGeometry.marqueeRect(from: anchor, to: NSPoint(x: 200, y: 300))
        let afterScroll = MediaScrollGeometry.marqueeRect(from: anchor, to: NSPoint(x: 200, y: 700))

        XCTAssertGreaterThan(afterScroll.height, beforeScroll.height)
        XCTAssertEqual(afterScroll.minY, anchor.y)
    }
}
