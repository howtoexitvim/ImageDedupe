import AppKit

/// `NSCollectionView` subclass that routes native key and click events into the shared
/// selection model, using four-direction navigation.
///
/// Rubber-band selection is intentionally absent. It was dropped on 2026-08-15; Shift,
/// Command, double-click, and the keyboard cover multi-selection.
@MainActor
final class MediaNativeCollectionView: NSCollectionView {
    weak var coordinator: MediaCollectionView.Coordinator?

    private var autoScrollTimer: Timer?
    private var lastDragPointInWindow: NSPoint?
    /// In document coordinates, so the marquee stays anchored to content during scrolling.
    private var marqueeAnchor: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    /// The sidebar's SwiftUI list otherwise keeps first responder, which sends the arrow
    /// keys to All Media/Duplicates instead of the media tiles.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            let responder = window.firstResponder
            let isTextEditing = responder is NSText || responder is NSTextView
            if !isTextEditing {
                window.makeFirstResponder(self)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        coordinator?.viewModel.setFocusOwner(.mediaBrowser)
        coordinator?.refreshVisibleDecoration()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if coordinator?.viewModel.selection.focusOwner == .mediaBrowser {
            coordinator?.viewModel.setFocusOwner(.none)
        }
        coordinator?.refreshVisibleDecoration()
        return super.resignFirstResponder()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let coordinator,
              let key = MediaTableController.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        guard coordinator.viewModel.selection.focusOwner == .mediaBrowser else {
            super.keyDown(with: event)
            return
        }

        let modifiers = MediaTableController.Modifiers(event.modifierFlags)
        let extending = modifiers.contains(.shift)
        let columnCount = coordinator.currentColumnCount
        let viewModel = coordinator.viewModel

        var handled = true
        switch key {
        case .up:
            handled = viewModel.moveFocus(rows: -1, columns: 0, columnCount: columnCount, extendingSelection: extending) != nil
        case .down:
            handled = viewModel.moveFocus(rows: 1, columns: 0, columnCount: columnCount, extendingSelection: extending) != nil
        case .left:
            handled = viewModel.moveFocus(rows: 0, columns: -1, columnCount: columnCount, extendingSelection: extending) != nil
        case .right:
            handled = viewModel.moveFocus(rows: 0, columns: 1, columnCount: columnCount, extendingSelection: extending) != nil
        case .space:
            handled = viewModel.toggleFocusedItem()
        case .escape:
            handled = viewModel.clearSelection()
        case .enter:
            handled = false
        case .selectAll:
            viewModel.selectAllVisible()
        }

        guard handled else {
            super.keyDown(with: event)
            return
        }
        coordinator.scrollFocusIntoView()
        coordinator.refreshVisibleDecoration()
    }

    /// AppKit routes Command-A here before `keyDown`.
    override func selectAll(_ sender: Any?) {
        guard let coordinator,
              coordinator.viewModel.selection.focusOwner == .mediaBrowser else { return }
        coordinator.viewModel.selectAllVisible()
        coordinator.refreshVisibleDecoration()
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
        guard let index = coordinator.index(at: point) else {
            // Blank canvas starts a marquee. A click that never travels far enough stays a
            // plain click and only takes focus; it does not clear the selection, which
            // remains an explicit Escape action.
            trackMarquee(startingAt: point, initialEvent: event)
            return
        }

        if event.clickCount >= 2 {
            coordinator.doubleClick(index: index)
            return
        }

        coordinator.click(index: index, modifiers: MediaTableController.Modifiers(event.modifierFlags))
    }

    // MARK: - Marquee selection

    /// Rubber-band selection with edge auto-scroll, mirroring the List's drag behaviour.
    ///
    /// The anchor is kept in document coordinates so the marquee stays pinned to content
    /// while auto-scroll moves the viewport underneath it.
    private func trackMarquee(startingAt anchor: NSPoint, initialEvent: NSEvent) {
        guard let coordinator else { return }
        let origin = initialEvent.locationInWindow
        var didBegin = false

        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { break }

            if !didBegin {
                let travelled = hypot(
                    event.locationInWindow.x - origin.x,
                    event.locationInWindow.y - origin.y
                )
                guard travelled >= MediaTableMetrics.dragActivationDistance else { continue }
                let modifiers = MediaTableController.Modifiers(event.modifierFlags)
                coordinator.viewModel.beginMarqueeSelection(
                    additive: modifiers.contains(.command) || modifiers.contains(.shift)
                )
                marqueeAnchor = anchor
                didBegin = true
            }

            lastDragPointInWindow = event.locationInWindow
            updateMarquee(to: convert(event.locationInWindow, from: nil))
            updateAutoScroll(for: event)
        }

        stopAutoScroll()
        if didBegin {
            coordinator.viewModel.endDragSelection()
            coordinator.endMarquee()
            marqueeAnchor = nil
            coordinator.refreshVisibleDecoration()
        }
    }

    private func updateMarquee(to point: NSPoint) {
        guard let coordinator, let anchor = marqueeAnchor else { return }
        let rect = MediaScrollGeometry.marqueeRect(from: anchor, to: point)
        coordinator.showMarquee(rect)
        coordinator.viewModel.updateMarqueeSelection(intersecting: coordinator.itemIDs(intersecting: rect))
        coordinator.refreshVisibleDecoration()
    }

    // MARK: - Auto-scroll

    private func updateAutoScroll(for event: NSEvent) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let pointInClip = clipView.convert(event.locationInWindow, from: nil)
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

        let maxOriginY = max(0, bounds.height - clipView.bounds.height)
        let newOriginY = min(max(clipView.bounds.origin.y + velocity, 0), maxOriginY)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: newOriginY))
        enclosingScrollView?.reflectScrolledClipView(clipView)

        // The pointer has not moved, but the content under it has, so the marquee must
        // grow to cover the newly revealed items.
        updateMarquee(to: convert(pointInWindow, from: nil))
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = coordinator.index(at: point) else { return nil }
        return coordinator.contextMenu(forIndex: index)
    }
}
