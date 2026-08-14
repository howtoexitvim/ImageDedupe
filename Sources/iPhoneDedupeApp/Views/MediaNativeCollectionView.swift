import AppKit

/// `NSCollectionView` subclass that routes native key and click events into the shared
/// selection model, using four-direction navigation.
///
/// Rubber-band selection is intentionally absent. It was dropped on 2026-08-15; Shift,
/// Command, double-click, and the keyboard cover multi-selection.
@MainActor
final class MediaNativeCollectionView: NSCollectionView {
    weak var coordinator: MediaCollectionView.Coordinator?

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
            // A click on empty canvas only takes focus; it does not clear the selection,
            // which stays an explicit Escape action.
            coordinator.refreshVisibleDecoration()
            return
        }

        if event.clickCount >= 2 {
            coordinator.doubleClick(index: index)
        } else {
            coordinator.click(index: index, modifiers: MediaTableController.Modifiers(event.modifierFlags))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = coordinator.index(at: point) else { return nil }
        return coordinator.contextMenu(forIndex: index)
    }
}
