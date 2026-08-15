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

    /// Whether a drag at `pointInWindow` should still extend the selection.
    ///
    /// Vertical overshoot past the viewport is allowed and expected: holding the pointer
    /// below the last visible row is exactly how edge auto-scroll walks to the end of a
    /// long catalog, so the row is clamped to the nearest edge and the selection grows.
    ///
    /// Leaving the **window** is different. There the user has taken the pointer somewhere
    /// with no relationship to the list, and continuing to select items they cannot see is
    /// surprising. This is checked in window coordinates for exactly that reason.
    static func dragShouldExtend(pointInWindow: NSPoint, windowBounds: NSRect) -> Bool {
        windowBounds.contains(pointInWindow)
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
