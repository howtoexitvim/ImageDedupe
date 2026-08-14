import AppKit

/// `NSTableView` subclass that routes native key and drag events through
/// `MediaTableController` into the shared selection model.
///
/// It handles events only; it never computes its own document geometry.
@MainActor
final class MediaNativeTableView: NSTableView {
    weak var coordinator: MediaTableView.Coordinator?

    private var autoScrollTimer: Timer?
    private var lastDragPointInWindow: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        coordinator?.viewModel.setFocusOwner(.mediaBrowser)
        return super.becomeFirstResponder()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let coordinator,
              let key = MediaTableController.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        let modifiers = MediaTableController.Modifiers(event.modifierFlags)
        if coordinator.controller.handleKey(key, modifiers: modifiers) {
            coordinator.scrollFocusIntoView()
            return
        }
        // Unconsumed keys keep their normal AppKit behavior, which is how Enter stays
        // unbound and how the search field can still receive type-ahead.
        super.keyDown(with: event)
    }

    /// AppKit routes Command-A here before `keyDown`, so the shared contract needs it too.
    override func selectAll(_ sender: Any?) {
        guard let coordinator else { return }
        _ = coordinator.controller.handleKey(.selectAll, modifiers: .command)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        coordinator.viewModel.setFocusOwner(.mediaBrowser)

        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else {
            super.mouseDown(with: event)
            return
        }

        let modifiers = MediaTableController.Modifiers(event.modifierFlags)
        coordinator.controller.click(row: clickedRow, modifiers: modifiers)

        guard !modifiers.contains(.shift) else { return }
        trackDragSelection(startingAt: clickedRow, initialEvent: event)
    }

    /// Drives contiguous drag selection with edge auto-scroll until mouse-up.
    private func trackDragSelection(startingAt startRow: Int, initialEvent: NSEvent) {
        guard let coordinator else { return }
        var didBeginDrag = false

        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { break }

            if !didBeginDrag {
                coordinator.controller.beginDrag(atRow: startRow)
                didBeginDrag = true
            }

            lastDragPointInWindow = event.locationInWindow
            let point = convert(event.locationInWindow, from: nil)
            let draggedRow = clampedRow(at: point)
            coordinator.controller.updateDrag(toRow: draggedRow)
            updateAutoScroll(for: event)
        }

        stopAutoScroll()
        if didBeginDrag {
            coordinator.controller.endDrag()
        }
    }

    /// Rows above the first or below the last still extend the selection to that edge,
    /// which is what makes edge auto-scroll feel native.
    private func clampedRow(at point: NSPoint) -> Int {
        let hit = row(at: point)
        if hit >= 0 { return hit }
        guard numberOfRows > 0 else { return -1 }
        return point.y < 0 ? 0 : numberOfRows - 1
    }

    // MARK: - Context menu

    /// Right-click targets the clicked row without disturbing an existing multi-selection,
    /// matching the previous SwiftUI behavior and Finder.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return nil }
        return coordinator.contextMenu(forRow: clickedRow)
    }

    // MARK: - Auto-scroll

    private func updateAutoScroll(for event: NSEvent) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let pointInClip = clipView.convert(event.locationInWindow, from: nil)
        // Flip into top-down coordinates so "near the top edge" is a small number.
        let pointerY = clipView.bounds.maxY - pointInClip.y
        let velocity = MediaTableMetrics.autoScrollVelocity(
            pointerY: pointerY,
            viewportHeight: clipView.bounds.height
        )

        if velocity == 0 {
            stopAutoScroll()
            return
        }
        guard autoScrollTimer == nil else { return }

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stepAutoScroll()
            }
        }
    }

    private func stepAutoScroll() {
        guard let clipView = enclosingScrollView?.contentView,
              let coordinator,
              let pointInWindow = lastDragPointInWindow else { return }

        let pointInClip = clipView.convert(pointInWindow, from: nil)
        let pointerY = clipView.bounds.maxY - pointInClip.y
        let velocity = MediaTableMetrics.autoScrollVelocity(
            pointerY: pointerY,
            viewportHeight: clipView.bounds.height
        )
        guard velocity != 0 else {
            stopAutoScroll()
            return
        }

        // Documents are flipped, so a positive velocity increases origin.y.
        let maxOriginY = max(0, bounds.height - clipView.bounds.height)
        let newOriginY = min(max(clipView.bounds.origin.y + velocity, 0), maxOriginY)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: newOriginY))
        enclosingScrollView?.reflectScrolledClipView(clipView)

        let point = convert(pointInWindow, from: nil)
        coordinator.controller.updateDrag(toRow: clampedRow(at: point))
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
}

/// Draws focus and action-selection states. They must stay visually distinct: an item can
/// be focused without being checked, and checked without being focused.
@MainActor
final class MediaTableRowView: NSTableRowView {
    var isActionSelected = false
    var isFocusedItem = false

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        if isActionSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            bounds.fill()
        } else if isFocusedItem {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            bounds.fill()
        }

        if isFocusedItem {
            NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
            let outline = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}
