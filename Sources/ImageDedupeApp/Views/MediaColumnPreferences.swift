import DeduperCore
import Foundation

extension Notification.Name {
    /// Posted by the Reset Layout menu command. The List renderer observes it so the menu
    /// does not need a reference to the live table.
    static let mediaResetLayout = Notification.Name("media.resetLayout")
}

/// Local persistence for column order, column widths, and the sort descriptor.
///
/// Everything read back from disk is validated against the current column model. A
/// preference file written by an older or newer build must never be able to produce an
/// unusable table — an unknown column is ignored, a missing one is appended, and a width
/// is clamped into the column's own bounds.
final class MediaColumnPreferences {
    private enum Key {
        static let order = "media.column.order"
        static let widths = "media.column.widths"
        static let sortField = "media.sort.field"
        static let sortOrder = "media.sort.order"
    }

    static let defaultSortField: MediaSortField = .timestamp
    static let defaultSortOrder: DeduperCore.SortOrder = .descending

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Order

    /// The persisted arrangement, repaired so it always contains every known column
    /// exactly once. Persisted entries keep their relative order; anything new is appended
    /// in its declared position.
    var columnOrder: [MediaTableColumn] {
        guard let stored = defaults.array(forKey: Key.order) as? [String] else {
            return MediaTableColumn.allCases
        }

        var seen = Set<MediaTableColumn>()
        var ordered: [MediaTableColumn] = []
        for identifier in stored {
            guard let column = MediaTableColumn(rawValue: identifier), !seen.contains(column) else { continue }
            seen.insert(column)
            ordered.append(column)
        }
        for column in MediaTableColumn.allCases where !seen.contains(column) {
            ordered.append(column)
        }
        return ordered
    }

    func setColumnOrder(_ columns: [MediaTableColumn]) {
        defaults.set(columns.map(\.identifier), forKey: Key.order)
    }

    // MARK: - Widths

    func width(for column: MediaTableColumn) -> CGFloat {
        let stored = defaults.dictionary(forKey: Key.widths)?[column.identifier] as? Double
        guard let stored, stored.isFinite else { return column.defaultWidth }
        return clamp(CGFloat(stored), for: column)
    }

    func setWidth(_ width: CGFloat, for column: MediaTableColumn) {
        guard width.isFinite else { return }
        var widths = defaults.dictionary(forKey: Key.widths) as? [String: Double] ?? [:]
        widths[column.identifier] = Double(clamp(width, for: column))
        defaults.set(widths, forKey: Key.widths)
    }

    private func clamp(_ width: CGFloat, for column: MediaTableColumn) -> CGFloat {
        min(max(width, column.minimumWidth), column.maximumWidth)
    }

    // MARK: - Sort

    var sortField: MediaSortField {
        guard let raw = defaults.string(forKey: Key.sortField),
              let field = MediaSortField(rawValue: raw) else { return Self.defaultSortField }
        return field
    }

    var sortOrder: DeduperCore.SortOrder {
        guard let raw = defaults.string(forKey: Key.sortOrder),
              let order = DeduperCore.SortOrder(rawValue: raw) else { return Self.defaultSortOrder }
        return order
    }

    func setSort(field: MediaSortField, order: DeduperCore.SortOrder) {
        defaults.set(field.rawValue, forKey: Key.sortField)
        defaults.set(order.rawValue, forKey: Key.sortOrder)
    }

    // MARK: - Reset

    /// Backs the Reset Layout action. Removing the keys restores the declared defaults
    /// rather than writing a second copy of them.
    func reset() {
        defaults.removeObject(forKey: Key.order)
        defaults.removeObject(forKey: Key.widths)
        defaults.removeObject(forKey: Key.sortField)
        defaults.removeObject(forKey: Key.sortOrder)
    }
}
