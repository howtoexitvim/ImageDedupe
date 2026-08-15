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

    /// The sidebar's SwiftUI `List` otherwise keeps first responder after launch, which
    /// sends the arrow keys to All Media/Duplicates instead of the media rows.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            // Only claim focus if nothing more specific already owns it, so this never
            // steals the search field mid-typing.
            let responder = window.firstResponder
            let isTextEditing = responder is NSText || responder is NSTextView
            if !isTextEditing {
                window.makeFirstResponder(self)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        coordinator?.viewModel.setFocusOwner(.mediaBrowser)
        coordinator?.refreshFocusDecoration()
        return super.becomeFirstResponder()
    }

    /// Losing first responder must release ownership, otherwise the model keeps claiming
    /// the media browser has focus while the sidebar or search field is actually driving
    /// the arrow keys.
    override func resignFirstResponder() -> Bool {
        if coordinator?.viewModel.selection.focusOwner == .mediaBrowser {
            coordinator?.viewModel.setFocusOwner(.none)
        }
        coordinator?.refreshFocusDecoration()
        return super.resignFirstResponder()
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
            // Scrolling can reuse row views, so decoration is refreshed after the scroll.
            coordinator.refreshFocusDecoration()
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

        if event.clickCount >= 2 {
            coordinator.controller.doubleClick(row: clickedRow)
            coordinator.refreshFocusDecoration()
            return
        }

        coordinator.controller.click(row: clickedRow, modifiers: modifiers)
        coordinator.refreshFocusDecoration()

        guard !modifiers.contains(.shift) else { return }
        trackDragSelection(startingAt: clickedRow, initialEvent: event)
    }

    /// Drives contiguous drag selection with edge auto-scroll until mouse-up.
    ///
    /// A drag only starts once the pointer has actually travelled past
    /// `MediaTableMetrics.dragActivationDistance`. Without that threshold a click with the
    /// slightest hand tremor emits a `leftMouseDragged` event and silently checks the row,
    /// which made a plain click select an item unpredictably.
    private func trackDragSelection(startingAt startRow: Int, initialEvent: NSEvent) {
        guard let coordinator else { return }
        var didBeginDrag = false
        let origin = initialEvent.locationInWindow

        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { break }

            if !didBeginDrag {
                let travelled = hypot(
                    event.locationInWindow.x - origin.x,
                    event.locationInWindow.y - origin.y
                )
                guard travelled >= MediaTableMetrics.dragActivationDistance else { continue }
                coordinator.controller.beginDrag(atRow: startRow)
                didBeginDrag = true
            }

            // Dragging above or below the list keeps auto-scrolling, even off the window,
            // which is what makes long selections possible. Only a pointer that has
            // wandered far sideways stops extending.
            let pointInView = convert(event.locationInWindow, from: nil)
            guard MediaScrollGeometry.dragShouldExtend(at: pointInView, viewport: visibleRect) else {
                stopAutoScroll()
                continue
            }

            lastDragPointInWindow = event.locationInWindow
            let point = pointInView
            let draggedRow = clampedRow(at: point)
            coordinator.controller.updateDrag(toRow: draggedRow)
            coordinator.refreshFocusDecoration()
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
        let pointerY = MediaScrollGeometry.pointerDepth(of: event.locationInWindow, in: clipView)
        let velocity = MediaTableMetrics.autoScrollVelocity(
            pointerY: pointerY,
            viewportHeight: clipView.bounds.height
        )

        if velocity == 0 {
            stopAutoScroll()
            return
        }
        guard autoScrollTimer == nil else { return }

        // `Timer.scheduledTimer` only registers for `.default` run loop mode, but AppKit
        // runs in `.eventTracking` while the mouse is down, so such a timer never fires
        // during a drag — which is why auto-scroll appeared not to work at all. Adding the
        // timer to `.common` covers both modes.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stepAutoScroll()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private func stepAutoScroll() {
        guard let clipView = enclosingScrollView?.contentView,
              let coordinator,
              let pointInWindow = lastDragPointInWindow else { return }

        let pointerY = MediaScrollGeometry.pointerDepth(of: pointInWindow, in: clipView)
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
        coordinator.refreshFocusDecoration()
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
    var isActionSelected = false {
        didSet { if isActionSelected != oldValue { needsDisplay = true } }
    }

    var isFocusedItem = false {
        didSet { if isFocusedItem != oldValue { needsDisplay = true } }
    }

    /// Whether the media browser currently owns key input. The focus ring is drawn
    /// stronger when it does, so the user can tell where the arrow keys will land.
    var isBrowserFocused = false {
        didSet { if isBrowserFocused != oldValue { needsDisplay = true } }
    }

    /// Spoken description of the row's item, shared with the Grid tile so VoiceOver
    /// announces the same information in either renderer.
    var accessibilityDescription: String? {
        didSet {
            guard let accessibilityDescription else { return }
            setAccessibilityLabel(accessibilityDescription)
            setAccessibilityRole(.row)
            setAccessibilityElement(true)
        }
    }

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
            NSColor.controlAccentColor
                .withAlphaComponent(isBrowserFocused ? 0.9 : 0.4)
                .setStroke()
            let outline = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            outline.lineWidth = isBrowserFocused ? 2 : 1
            outline.stroke()
        }
    }
}
