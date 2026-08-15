import AppKit
import DeduperCore

/// The List's column model.
///
/// Widths live here and nowhere else. The table's document width is the sum of its own
/// column widths; no value in this file may be derived from sidebar or window geometry.
/// That inversion is what caused the 2026-08-15 layout regression.
enum MediaTableColumn: String, CaseIterable {
    case selection
    case thumbnail
    case name
    case kind
    case timestamp
    case size
    case duration

    var identifier: String { rawValue }

    var userInterfaceIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var title: String {
        switch self {
        case .selection: return ""
        case .thumbnail: return ""
        case .name: return "Name"
        case .kind: return "Kind"
        case .timestamp: return "Date"
        case .size: return "File Size"
        case .duration: return "Duration"
        }
    }

    /// Sortable data columns only. The checkbox and thumbnail columns have no sort meaning.
    var sortField: MediaSortField? {
        switch self {
        case .selection, .thumbnail: return nil
        case .name: return .name
        case .kind: return .kind
        case .timestamp: return .timestamp
        case .size: return .size
        case .duration: return .duration
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .selection: return 28
        case .thumbnail: return 28
        // Name keeps a floor well above the checkbox/thumbnail pair so a narrow drag can
        // never overlap that geometry.
        case .name: return 140
        case .kind: return 54
        case .timestamp: return 120
        case .size: return 86
        case .duration: return 72
        }
    }

    var maximumWidth: CGFloat {
        switch self {
        case .selection, .thumbnail: return 96
        case .name: return 1_200
        case .kind: return 200
        case .timestamp: return 320
        case .size: return 200
        case .duration: return 200
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .selection: return 28
        case .thumbnail: return 44
        case .name: return 280
        case .kind: return 54
        case .timestamp: return 190
        case .size: return 86
        case .duration: return 72
        }
    }

    var alignment: NSTextAlignment {
        switch self {
        case .size, .duration: return .right
        default: return .left
        }
    }

    /// Name is the column that absorbs leftover width, matching Finder.
    var isFlexible: Bool { self == .name }

    /// The checkbox and thumbnail are row furniture that must stay pinned to the leading
    /// edge. Letting a header drag move them would put the checkbox mid-row.
    var isReorderable: Bool {
        switch self {
        case .selection, .thumbnail: return false
        default: return true
        }
    }

    static var totalDefaultWidth: CGFloat {
        allCases.reduce(0) { $0 + $1.defaultWidth }
    }

    static func column(for identifier: NSUserInterfaceItemIdentifier) -> MediaTableColumn? {
        MediaTableColumn(rawValue: identifier.rawValue)
    }
}

enum MediaTableMetrics {
    static let minimumRowHeight: CGFloat = 24
    static let rowVerticalPadding: CGFloat = 10

    /// Height of a duplicate group's header row. Fixed, and independent of thumbnail size:
    /// a header carries one line of text whatever the tiles are scaled to.
    static let groupHeaderHeight: CGFloat = 24

    static func rowHeight(thumbnailSide: Double) -> CGFloat {
        max(minimumRowHeight, CGFloat(thumbnailSide) + rowVerticalPadding)
    }

    /// How far the pointer must travel before a press becomes a drag selection. Below
    /// this, the gesture stays a plain click, which only moves focus.
    static let dragActivationDistance: CGFloat = 4

    /// Distance from a viewport edge within which a drag starts auto-scrolling.
    ///
    /// Finder and Explorer both start scrolling from a band *inside* the edge, then hold
    /// full speed for as long as the pointer stays beyond it — including outside the
    /// window. A wider band than the previous 24 pt makes the gesture much easier to find.
    static let autoScrollMargin: CGFloat = 48
    static let maximumAutoScrollVelocity: CGFloat = 24

    /// Points-per-tick scroll velocity for a drag at `pointerY`, measured from the top of
    /// the viewport. Negative scrolls toward the top, positive toward the bottom, zero is
    /// idle.
    ///
    /// Two rules, both matching Finder:
    ///
    /// - Inside the edge band, speed ramps up as the pointer approaches the edge, so slow
    ///   precise dragging near the boundary does not lurch.
    /// - **Past** the edge, speed pins to the maximum and stays there. Earlier this clamped
    ///   the pointer back into the viewport, which made a drag well past the boundary
    ///   compute a smaller depth and even pick the wrong branch, so scrolling would stall
    ///   or reverse direction.
    static func autoScrollVelocity(pointerY: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > autoScrollMargin * 2 else { return 0 }

        if pointerY < autoScrollMargin {
            // Beyond the top edge: full speed upward, never reversing.
            guard pointerY > 0 else { return -maximumAutoScrollVelocity }
            let depth = (autoScrollMargin - pointerY) / autoScrollMargin
            return -depth * maximumAutoScrollVelocity
        }

        let bottomEdge = viewportHeight - autoScrollMargin
        if pointerY > bottomEdge {
            // Beyond the bottom edge: full speed downward, never reversing.
            guard pointerY < viewportHeight else { return maximumAutoScrollVelocity }
            let depth = (pointerY - bottomEdge) / autoScrollMargin
            return depth * maximumAutoScrollVelocity
        }
        return 0
    }
}
