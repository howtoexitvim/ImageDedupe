import AppKit

/// The three panes of the browser window.
///
/// Pane widths live here. Center renderers consume their actual bounds and never subtract
/// these values — that inversion caused the 2026-08-15 layout regression.
enum MediaPane: String, CaseIterable {
    case sidebar
    case inspector

    var identifier: String { rawValue }

    var minimumWidth: CGFloat {
        switch self {
        case .sidebar: return 180
        case .inspector: return 260
        }
    }

    var maximumWidth: CGFloat {
        switch self {
        case .sidebar: return 320
        case .inspector: return 420
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .sidebar: return 220
        case .inspector: return 300
        }
    }
}

enum MediaPaneLayout {
    static let minimumCenterWidth: CGFloat = 480
    static let minimumWindowHeight: CGFloat = 600

    /// The window cannot be narrower than every pane's minimum, or the split view is asked
    /// to satisfy constraints that do not fit and the center browser gets squeezed until
    /// its leading columns clip.
    ///
    /// This is derived rather than hard-coded: the previous 940 pt literal drifted out of
    /// agreement with the pane minimums it was supposed to accommodate.
    ///
    /// The sidebar term uses its *ideal* width, not its minimum. Showing the inspector
    /// inserts a whole pane into an already-minimum window, and with only the minimums
    /// summed there is exactly zero slack — any sidebar wider than 180 pt immediately
    /// pushes the center under its own minimum and clips the leading columns.
    static var minimumWindowWidth: CGFloat {
        MediaPane.sidebar.defaultWidth + minimumCenterWidth + MediaPane.inspector.minimumWidth
    }

    /// Room left for the center browser.
    ///
    /// Reported for status and tests only. The center renderers read their own bounds and
    /// must never compute their document origin from this value.
    static func centerWidth(
        windowWidth: CGFloat,
        sidebarWidth: CGFloat,
        inspectorWidth: CGFloat,
        isSidebarCollapsed: Bool,
        isInspectorCollapsed: Bool
    ) -> CGFloat {
        let leading = isSidebarCollapsed ? 0 : sidebarWidth
        let trailing = isInspectorCollapsed ? 0 : inspectorWidth
        return max(0, windowWidth - leading - trailing)
    }
}

/// Local persistence for pane widths and collapsed state.
///
/// Mirrors `MediaColumnPreferences`: everything read back from disk is validated against
/// the current pane contract, so an old or corrupt preference file cannot produce an
/// unusable window.
final class MediaPanePreferences {
    private enum Key {
        static let widths = "media.pane.widths"
        static let collapsed = "media.pane.collapsed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Widths

    /// The width to use when the pane is showing. A collapsed pane keeps this value so it
    /// restores to where the user left it rather than to the minimum.
    func width(for pane: MediaPane) -> CGFloat {
        let stored = defaults.dictionary(forKey: Key.widths)?[pane.identifier] as? Double
        guard let stored, stored.isFinite else { return pane.defaultWidth }
        return clamp(CGFloat(stored), for: pane)
    }

    func setWidth(_ width: CGFloat, for pane: MediaPane) {
        guard width.isFinite else { return }
        var widths = defaults.dictionary(forKey: Key.widths) as? [String: Double] ?? [:]
        widths[pane.identifier] = Double(clamp(width, for: pane))
        defaults.set(widths, forKey: Key.widths)
    }

    private func clamp(_ width: CGFloat, for pane: MediaPane) -> CGFloat {
        min(max(width, pane.minimumWidth), pane.maximumWidth)
    }

    // MARK: - Collapse

    func isCollapsed(_ pane: MediaPane) -> Bool {
        defaults.dictionary(forKey: Key.collapsed)?[pane.identifier] as? Bool ?? false
    }

    func setCollapsed(_ isCollapsed: Bool, for pane: MediaPane) {
        var collapsed = defaults.dictionary(forKey: Key.collapsed) as? [String: Bool] ?? [:]
        collapsed[pane.identifier] = isCollapsed
        defaults.set(collapsed, forKey: Key.collapsed)
    }

    // MARK: - Reset

    /// Part of Reset Layout, alongside `MediaColumnPreferences.reset()`. Removing the keys
    /// restores the declared defaults rather than writing a second copy of them.
    func reset() {
        defaults.removeObject(forKey: Key.widths)
        defaults.removeObject(forKey: Key.collapsed)
    }
}
