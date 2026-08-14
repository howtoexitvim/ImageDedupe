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

    static func rowHeight(thumbnailSide: Double) -> CGFloat {
        max(minimumRowHeight, CGFloat(thumbnailSide) + rowVerticalPadding)
    }

    /// Distance from a viewport edge within which a drag starts auto-scrolling.
    static let autoScrollMargin: CGFloat = 24
    static let maximumAutoScrollVelocity: CGFloat = 18

    /// Points-per-tick scroll velocity for a drag at `pointerY` inside the viewport.
    /// Negative scrolls toward the top, positive toward the bottom, zero is idle.
    /// Velocity increases closer to the edge so a slow drag still reaches distant rows.
    static func autoScrollVelocity(pointerY: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > autoScrollMargin * 2 else { return 0 }

        if pointerY < autoScrollMargin {
            let depth = (autoScrollMargin - max(pointerY, 0)) / autoScrollMargin
            return -depth * maximumAutoScrollVelocity
        }
        let bottomEdge = viewportHeight - autoScrollMargin
        if pointerY > bottomEdge {
            let depth = (min(pointerY, viewportHeight) - bottomEdge) / autoScrollMargin
            return depth * maximumAutoScrollVelocity
        }
        return 0
    }
}
