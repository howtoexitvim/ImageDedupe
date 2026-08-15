import AppKit
import XCTest
@testable import ImageDedupeApp

/// Keyboard scroll-into-view and drag edge auto-scroll geometry.
///
/// Both renderers share this maths so List and Grid feel identical. Everything here is a
/// pure function of rectangles, so it is testable without a window or a run loop.
@MainActor
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

    // MARK: - Pointer depth in flipped and unflipped clip views

    /// Builds a view inside a real window, because `convert(_:from: nil)` only performs a
    /// genuine flip when the view actually belongs to a window.
    private func hostedView(flipped: Bool) -> NSView {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = flipped
            ? FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            : NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView?.addSubview(view)
        return view
    }

    /// Regression: the pointer depth subtracted from `bounds.maxY` unconditionally. Table
    /// and collection views are flipped, and `convert(_:from: nil)` already returns
    /// top-down coordinates for them, so flipping again reversed the scroll direction —
    /// dragging below the list scrolled *up*.
    func testPointerDepthMeasuresFromTheTopInAFlippedView() {
        let clip = hostedView(flipped: true)

        // Window y grows upward, so a small window y is near the *bottom* of the view.
        let depthAtWindowBottom = MediaScrollGeometry.pointerDepth(of: NSPoint(x: 10, y: 10), in: clip)
        let depthAtWindowTop = MediaScrollGeometry.pointerDepth(of: NSPoint(x: 10, y: 290), in: clip)

        XCTAssertEqual(depthAtWindowBottom, 290, "near the window bottom is deep into the view")
        XCTAssertEqual(depthAtWindowTop, 10, "near the window top is shallow")
    }

    func testPointerDepthMeasuresFromTheTopInAnUnflippedView() {
        let clip = hostedView(flipped: false)

        let depthAtWindowBottom = MediaScrollGeometry.pointerDepth(of: NSPoint(x: 10, y: 10), in: clip)
        let depthAtWindowTop = MediaScrollGeometry.pointerDepth(of: NSPoint(x: 10, y: 290), in: clip)

        // Same answer as the flipped case: the helper's whole job is to normalize this.
        XCTAssertEqual(depthAtWindowBottom, 290)
        XCTAssertEqual(depthAtWindowTop, 10)
    }

    /// The behaviour the user reported: dragging below the content must scroll down.
    func testDraggingBelowTheContentScrollsDown() {
        let clip = hostedView(flipped: true)
        let depth = MediaScrollGeometry.pointerDepth(of: NSPoint(x: 10, y: -200), in: clip)
        let velocity = MediaTableMetrics.autoScrollVelocity(pointerY: depth, viewportHeight: 300)

        XCTAssertGreaterThan(velocity, 0, "below the content must scroll down, not up")
    }

    func testDraggingAboveTheContentScrollsUp() {
        let clip = hostedView(flipped: true)
        let depth = MediaScrollGeometry.pointerDepth(of: NSPoint(x: 10, y: 500), in: clip)
        let velocity = MediaTableMetrics.autoScrollVelocity(pointerY: depth, viewportHeight: 300)

        XCTAssertLessThan(velocity, 0, "above the content must scroll up, not down")
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

    /// The overlay draws a rect that was computed in the collection view's flipped
    /// document space, so the overlay must be flipped too.
    ///
    /// When it was not, `draw(_:)` measured `marqueeRect.y` from the bottom of a
    /// document-sized view while the rect measured it from the top. That mirrors the
    /// rectangle about the document's vertical midpoint, which is the pointer offset
    /// reported on 2026-08-15: small near the middle, hundreds of points near either end,
    /// and growing with the length of the catalog.
    @MainActor
    func testMarqueeOverlaySharesTheFlippedDocumentSpace() {
        XCTAssertTrue(
            MediaMarqueeOverlayView().isFlipped,
            "An unflipped overlay mirrors the marquee vertically against a flipped grid."
        )
        XCTAssertTrue(
            NSCollectionView().isFlipped,
            "This test only means anything while the document view is flipped."
        )
    }

    /// The mirroring an unflipped overlay produced, stated as arithmetic so the size of the
    /// defect is on record: the further the drag is from the document's midpoint, the
    /// further the drawn rectangle lands from the pointer.
    func testUnflippedOverlayWouldMirrorTheMarqueeAboutTheDocumentMidpoint() {
        let documentHeight: CGFloat = 4000
        let rect = MediaScrollGeometry.marqueeRect(
            from: NSPoint(x: 40, y: 200),
            to: NSPoint(x: 240, y: 400)
        )

        // What an unflipped view draws when handed a flipped rect.
        let mirroredMinY = documentHeight - rect.maxY
        XCTAssertEqual(mirroredMinY, 3600)
        XCTAssertEqual(mirroredMinY - rect.minY, 3400, "The offset the user sees.")
    }
}

/// Stands in for a clip view enclosing a table or collection view, both of which are
/// flipped.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
