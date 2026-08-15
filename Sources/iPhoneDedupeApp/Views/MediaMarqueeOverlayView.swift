import AppKit

/// Draws the rubber-band rectangle above the Grid's tiles during a marquee drag.
///
/// Transparent to hit testing so it never swallows the drag it is illustrating, and it
/// draws in the collection view's document coordinates so the rectangle stays anchored to
/// content while edge auto-scroll moves the viewport underneath it.
@MainActor
final class MediaMarqueeOverlayView: NSView {
    var marqueeRect: NSRect = .zero {
        didSet { if marqueeRect != oldValue { needsDisplay = true } }
    }

    /// Matches `NSCollectionView`, which is flipped.
    ///
    /// `marqueeRect` is built from points converted out of the collection view, so its `y`
    /// is measured downward from the top of the document. An unflipped overlay measures
    /// upward from the bottom of a view spanning that same document, which mirrors the
    /// rectangle about the document's midpoint — the pointer offset reported on
    /// 2026-08-15. The offset looked like a constant inset only because it was measured at
    /// one scroll position; it in fact scales with the height of the catalog.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !marqueeRect.isEmpty else { return }

        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        marqueeRect.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: marqueeRect)
        border.lineWidth = 1
        border.stroke()
    }
}
