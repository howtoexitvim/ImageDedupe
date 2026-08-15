import Foundation

/// Deterministic focus and action-selection model shared by the List and Grid renderers.
///
/// The renderers own geometry; this type owns interaction meaning. It is pure value
/// state so the authoritative keyboard/mouse contract can be unit tested without AppKit,
/// ImageCaptureCore, or a running window.
///
/// Two selection concepts exist and never collapse into one:
/// - `focusedID` drives keyboard movement, scroll-into-view, and inspector content.
/// - `actionSelectedIDs` is the checked set consumed by Import and Delete.
struct MediaSelectionState: Equatable {
    /// Which region currently owns key input. Media shortcuts apply only to `mediaBrowser`.
    enum FocusOwner: Equatable {
        case none
        case mediaBrowser
        case search
        case inspector
    }

    private(set) var visibleIDs: [String] = []
    private var visibleIndexByID: [String: Int] = [:]

    var focusedID: String?
    var anchorID: String?
    var actionSelectedIDs: Set<String> = []
    var focusOwner: FocusOwner = .none

    /// IDs selected before the in-progress drag began, so a drag can shrink its own
    /// range without discarding earlier selection.
    private var dragBaseSelection: Set<String>?
    private var dragOriginID: String?

    /// The same idea for keyboard/click extension: the selection as it stood before the
    /// current anchor's extension started. Shrinking the range restores from this base,
    /// so selection made outside the extension survives.
    private var extensionBaseSelection: Set<String>?
    private var extensionAnchorID: String?

    init() {}

    // MARK: - Visible order

    /// Publishes the current filtered/sorted order and reconciles focus, anchor, and
    /// action selection against it. Anything no longer visible is dropped.
    mutating func setVisibleIDs(_ ids: [String]) {
        var ordered: [String] = []
        var indexByID: [String: Int] = [:]
        ordered.reserveCapacity(ids.count)
        for id in ids where indexByID[id] == nil {
            indexByID[id] = ordered.count
            ordered.append(id)
        }
        visibleIDs = ordered
        visibleIndexByID = indexByID
        reconcile()
    }

    private mutating func reconcile() {
        if let focusedID, visibleIndexByID[focusedID] == nil {
            self.focusedID = nil
        }
        if let anchorID, visibleIndexByID[anchorID] == nil {
            self.anchorID = nil
        }
        actionSelectedIDs = actionSelectedIDs.filter { visibleIndexByID[$0] != nil }
        if let dragBaseSelection {
            self.dragBaseSelection = dragBaseSelection.filter { visibleIndexByID[$0] != nil }
        }
        if let dragOriginID, visibleIndexByID[dragOriginID] == nil {
            self.dragOriginID = nil
        }
        if let extensionBaseSelection {
            self.extensionBaseSelection = extensionBaseSelection.filter { visibleIndexByID[$0] != nil }
        }
        if let extensionAnchorID, visibleIndexByID[extensionAnchorID] == nil {
            self.extensionAnchorID = nil
            self.extensionBaseSelection = nil
        }
    }

    var focusedIndex: Int? {
        guard let focusedID else { return nil }
        return visibleIndexByID[focusedID]
    }

    func contains(_ id: String) -> Bool {
        visibleIndexByID[id] != nil
    }

    func index(of id: String) -> Int? {
        visibleIndexByID[id]
    }

    // MARK: - Keyboard focus movement

    /// Moves focus by a signed offset in visible order, clamping at both edges.
    ///
    /// Returns the newly focused ID so the renderer can scroll it into view, or `nil`
    /// when the media browser does not own focus or there is nothing to focus.
    @discardableResult
    mutating func moveFocus(by offset: Int, extendingSelection: Bool) -> String? {
        guard focusOwner == .mediaBrowser, !visibleIDs.isEmpty else { return nil }

        let targetIndex: Int
        if let currentIndex = focusedIndex {
            targetIndex = clampIndex(currentIndex + offset)
        } else {
            targetIndex = offset >= 0 ? 0 : visibleIDs.count - 1
        }
        return applyFocus(atIndex: targetIndex, extendingSelection: extendingSelection)
    }

    /// Grid movement. `rows` steps by the measured column count; `columns` steps by one item.
    @discardableResult
    mutating func moveFocus(rows: Int, columns: Int, columnCount: Int, extendingSelection: Bool) -> String? {
        let stride = max(1, columnCount)
        return moveFocus(by: rows * stride + columns, extendingSelection: extendingSelection)
    }

    private mutating func applyFocus(atIndex index: Int, extendingSelection: Bool) -> String? {
        guard visibleIDs.indices.contains(index) else { return nil }
        let id = visibleIDs[index]

        if extendingSelection {
            let anchor = anchorID ?? focusedID ?? id
            anchorID = anchor
            focusedID = id
            selectRange(from: anchor, to: id)
        } else {
            focusedID = id
            anchorID = id
            endExtension()
        }
        return id
    }

    private func clampIndex(_ index: Int) -> Int {
        min(max(index, 0), max(visibleIDs.count - 1, 0))
    }

    // MARK: - Mouse focus and toggling

    /// A plain item click: moves focus and the anchor, leaves the action selection alone.
    mutating func focus(_ id: String) {
        guard contains(id) else { return }
        focusOwner = .mediaBrowser
        focusedID = id
        anchorID = id
        endExtension()
    }

    /// A checkbox click or context-menu toggle: changes only the action selection.
    mutating func toggleActionSelection(_ id: String) {
        guard contains(id) else { return }
        if actionSelectedIDs.contains(id) {
            actionSelectedIDs.remove(id)
        } else {
            actionSelectedIDs.insert(id)
        }
        anchorID = id
        endExtension()
    }

    /// Shift-click: extends the contiguous range from the stable anchor to `id`.
    mutating func extendSelection(to id: String) {
        guard contains(id) else { return }
        let anchor = anchorID ?? focusedID ?? id
        anchorID = anchor
        focusedID = id
        selectRange(from: anchor, to: id)
    }

    /// Space: toggles exactly the focused item. Returns whether anything changed.
    @discardableResult
    mutating func toggleFocusedItem() -> Bool {
        guard focusOwner == .mediaBrowser, let focusedID else { return false }
        toggleActionSelection(focusedID)
        return true
    }

    /// Command-A: selects the current filtered order only, and only when the media
    /// browser owns focus, so search text editing keeps its own Select All.
    @discardableResult
    mutating func selectAllVisible() -> Bool {
        guard focusOwner == .mediaBrowser else { return false }
        actionSelectedIDs = Set(visibleIDs)
        endExtension()
        return true
    }

    /// Escape: clears focus, anchor, and action selection. Inspector visibility is a
    /// separate concern and is deliberately untouched here.
    @discardableResult
    mutating func clearSelection() -> Bool {
        guard focusOwner == .mediaBrowser else { return false }
        guard focusedID != nil || anchorID != nil || !actionSelectedIDs.isEmpty else { return false }
        focusedID = nil
        anchorID = nil
        actionSelectedIDs.removeAll()
        endExtension()
        return true
    }

    // MARK: - Drag selection

    /// Whether the in-progress drag is removing rather than adding.
    ///
    /// Finder decides this from the item the drag starts on: begin on an unselected item
    /// and the drag selects; begin on a selected one and it deselects. Without this a drag
    /// could only ever add, so there was no way to undo part of a selection by dragging
    /// back over it.
    private var isDragDeselecting = false

    mutating func beginDragSelection(at id: String) {
        guard contains(id) else { return }
        focusOwner = .mediaBrowser
        isDragDeselecting = actionSelectedIDs.contains(id)
        dragBaseSelection = actionSelectedIDs
        dragOriginID = id
        anchorID = id
        focusedID = id
        if isDragDeselecting {
            actionSelectedIDs.remove(id)
        } else {
            actionSelectedIDs.insert(id)
        }
        endExtension()
    }

    /// Applies the drag's range on top of the selection as it stood before the drag, either
    /// adding or removing depending on where the drag started. Shrinking the range restores
    /// the rows it no longer covers.
    mutating func updateDragSelection(to id: String) {
        guard contains(id), let origin = dragOriginID, let base = dragBaseSelection else { return }
        focusedID = id
        let range = ids(from: origin, to: id)
        actionSelectedIDs = isDragDeselecting ? base.subtracting(range) : base.union(range)
    }

    /// Starts a marquee drag from blank canvas, where there is no origin item.
    ///
    /// Additive drags (Command or Shift held) keep the existing selection as their base;
    /// a plain drag replaces it, matching Finder.
    mutating func beginMarqueeSelection(additive: Bool, deselecting: Bool = false) {
        focusOwner = .mediaBrowser
        isDragDeselecting = deselecting
        dragBaseSelection = (additive || deselecting) ? actionSelectedIDs : []
        dragOriginID = nil
        isMarqueeSelecting = true
        if !additive && !deselecting {
            actionSelectedIDs.removeAll()
        }
        endExtension()
    }

    /// Replaces the marquee's contribution with the items it currently intersects, leaving
    /// any pre-drag selection intact. Shrinking the marquee therefore deselects only what
    /// the marquee itself added.
    mutating func updateMarqueeSelection(intersecting ids: Set<String>) {
        guard isMarqueeSelecting, let base = dragBaseSelection else { return }
        let valid = Set(ids.filter { contains($0) })
        actionSelectedIDs = isDragDeselecting ? base.subtracting(valid) : base.union(valid)
    }

    mutating func endDragSelection() {
        dragBaseSelection = nil
        dragOriginID = nil
        isMarqueeSelecting = false
        isDragDeselecting = false
    }

    private var isMarqueeSelecting = false

    var isDragSelecting: Bool {
        dragOriginID != nil || isMarqueeSelecting
    }

    // MARK: - Ranges

    /// Applies the anchor-to-target range on top of the selection as it stood before this
    /// extension began, so reversing direction shrinks the range instead of leaving a
    /// stale tail behind.
    private mutating func selectRange(from anchor: String, to target: String) {
        if extensionAnchorID != anchor || extensionBaseSelection == nil {
            extensionAnchorID = anchor
            extensionBaseSelection = actionSelectedIDs.subtracting([anchor])
        }
        let base = extensionBaseSelection ?? []
        actionSelectedIDs = base.union(ids(from: anchor, to: target))
    }

    /// Any action that establishes a fresh anchor ends the previous extension.
    private mutating func endExtension() {
        extensionAnchorID = nil
        extensionBaseSelection = nil
    }

    /// Contiguous IDs between two visible items, inclusive, in either direction.
    func ids(from anchor: String, to target: String) -> Set<String> {
        guard let anchorIndex = visibleIndexByID[anchor],
              let targetIndex = visibleIndexByID[target] else { return [] }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        return Set(visibleIDs[range])
    }

}
