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
