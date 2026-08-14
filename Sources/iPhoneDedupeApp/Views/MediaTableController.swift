import AppKit

/// Translates native table events into the shared selection model.
///
/// Keeping this separate from the `NSTableView` subclass means the authoritative keyboard
/// and drag contract is testable without a window, a run loop, or a real event stream.
@MainActor
final class MediaTableController {
    /// The keys the media browser understands. Anything else is left to AppKit.
    enum Key {
        case up
        case down
        case left
        case right
        case space
        case escape
        case enter
        case selectAll
    }

    struct Modifiers: OptionSet {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let command = Modifiers(rawValue: 1 << 1)

        init(rawValue: Int) { self.rawValue = rawValue }

        init(_ flags: NSEvent.ModifierFlags) {
            var result = Modifiers([])
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.command) { result.insert(.command) }
            self = result
        }
    }

    private let viewModel: MediaBrowserViewModel

    init(viewModel: MediaBrowserViewModel) {
        self.viewModel = viewModel
    }

    /// Returns whether the media browser consumed the key. `false` means AppKit should
    /// keep its default behavior, which is how Enter stays unbound and how Left/Right
    /// remain available to the table itself.
    @discardableResult
    func handleKey(_ key: Key, modifiers: Modifiers) -> Bool {
        guard viewModel.selection.focusOwner == .mediaBrowser else { return false }

        switch key {
        case .up:
            return viewModel.moveFocus(by: -1, extendingSelection: modifiers.contains(.shift)) != nil
        case .down:
            return viewModel.moveFocus(by: 1, extendingSelection: modifiers.contains(.shift)) != nil
        case .left, .right:
            // The List is one-dimensional; horizontal arrows belong to Grid and to
            // native horizontal scrolling.
            return false
        case .space:
            return viewModel.toggleFocusedItem()
        case .escape:
            return viewModel.clearSelection()
        case .enter:
            // Deliberately unbound. See roadmap non-goals.
            return false
        case .selectAll:
            guard modifiers.contains(.command) else { return false }
            viewModel.selectAllVisible()
            return true
        }
    }

    /// Maps an `NSEvent` to a `Key`, or `nil` when the media browser has no meaning for it.
    static func key(for event: NSEvent) -> Key? {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            return .selectAll
        }
        switch Int(event.keyCode) {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 49: return .space
        case 53: return .escape
        case 36, 76: return .enter
        default: return nil
        }
    }

    // MARK: - Row helpers

    private func id(atRow row: Int) -> String? {
        let ids = viewModel.selection.visibleIDs
        guard ids.indices.contains(row) else { return nil }
        return ids[row]
    }

    func row(for id: String) -> Int? {
        viewModel.selection.index(of: id)
    }

    /// A plain row click: moves focus and inspector content, never the action selection.
    /// Shift extends from the anchor; Command toggles one row, matching Finder.
    func click(row: Int, modifiers: Modifiers) {
        guard let id = id(atRow: row) else { return }
        if modifiers.contains(.shift) {
            viewModel.extendSelection(to: id)
        } else if modifiers.contains(.command) {
            viewModel.toggleActionSelection(withID: id)
        } else {
            viewModel.selectItem(withID: id)
        }
    }

    /// Double-click toggles the row's action selection, alongside Space and the checkbox.
    func doubleClick(row: Int) {
        guard let id = id(atRow: row) else { return }
        viewModel.selectItem(withID: id)
        viewModel.toggleActionSelection(withID: id)
    }

    // MARK: - Drag selection

    func beginDrag(atRow row: Int) {
        guard let id = id(atRow: row) else { return }
        viewModel.beginDragSelection(at: id)
    }

    func updateDrag(toRow row: Int) {
        guard let id = id(atRow: row) else { return }
        viewModel.updateDragSelection(to: id)
    }

    func endDrag() {
        viewModel.endDragSelection()
    }
}
