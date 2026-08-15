import AppKit

/// Scrolling geometry shared by the List and the Grid.
///
/// Both renderers use the same maths so keyboard navigation and drag auto-scroll feel
/// identical in either view. These are pure functions of rectangles: no view, window, or
/// run loop is involved, which is what makes the behaviour testable.
///
/// This is shared *state and maths*, not a shared layout object — the distinction the
/// 2026-08-15 layout incident established.
enum MediaScrollGeometry {
    /// Keeps this much of the neighbouring content visible around a focused item, instead
    /// of parking it flush against the viewport edge.
    ///
    /// `NSTableView.scrollRowToVisible` and `NSCollectionView.scrollToItems` both scroll
    /// the minimum distance, which lands the focused item exactly on the edge with no
    /// context. That reads as "it did not scroll".
    static let keyboardRevealPadding: CGFloat = 24

    /// The new vertical scroll origin needed to reveal `item`, or `nil` when the item is
    /// already comfortably visible and no scrolling is required.
    ///
    /// All rectangles are in the document's (flipped) coordinate space.
    static func originToRevealItem(
        _ item: NSRect,
        in viewport: NSRect,
        padding: CGFloat = keyboardRevealPadding
    ) -> CGFloat? {
        // An item taller than the viewport can never satisfy both edges; align its top.
        guard item.height + padding * 2 <= viewport.height else {
            return item.minY == viewport.minY ? nil : item.minY
        }

        let desiredTop = item.minY - padding
        let desiredBottom = item.maxY + padding

        if desiredTop < viewport.minY {
            let origin = max(0, desiredTop)
            return origin == viewport.minY ? nil : origin
        }
        if desiredBottom > viewport.maxY {
            let origin = max(0, desiredBottom - viewport.height)
            return origin == viewport.minY ? nil : origin
        }
        return nil
    }

    /// How far horizontally outside the browser a drag may stray before it stops
    /// extending. Vertical overshoot is deliberately unlimited.
    static let horizontalDragAbandonMargin: CGFloat = 160

    /// Whether a drag at `point` should still extend the selection.
    ///
    /// This models Finder and Explorer, where dragging *above or below* the list — even
    /// off the window and across the desktop — keeps auto-scrolling and selecting. That is
    /// the whole point of edge auto-scroll: the pointer must be able to rest outside the
    /// bounds while the content streams past it. So vertical overshoot is unlimited.
    ///
    /// Horizontal overshoot is different. A pointer dragged far to the left or right has
    /// left the list entirely, and continuing to select there is the surprising behaviour
    /// reported on 2026-08-15. A generous margin keeps ordinary sloppy dragging working
    /// while stopping a pointer that has genuinely wandered off.
    ///
    /// `point` and `viewport` must share a coordinate space.
    static func dragShouldExtend(at point: NSPoint, viewport: NSRect) -> Bool {
        point.x >= viewport.minX - horizontalDragAbandonMargin
            && point.x <= viewport.maxX + horizontalDragAbandonMargin
    }

    /// The marquee rectangle between two points, normalized so dragging in any direction
    /// produces a positive-size rect.
    ///
    /// Both points must be in **document** coordinates. Keeping the anchor in document
    /// space is what pins the marquee to the content while auto-scroll moves the viewport
    /// underneath it; an anchor in view coordinates would drift with the scroll.
    static func marqueeRect(from anchor: NSPoint, to current: NSPoint) -> NSRect {
        NSRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        )
    }
}
