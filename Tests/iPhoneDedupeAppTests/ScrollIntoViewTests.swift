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
