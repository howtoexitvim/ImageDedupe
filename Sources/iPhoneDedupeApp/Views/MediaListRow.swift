import DeduperCore
import Foundation

/// A row in the List: either a group header or a media item.
///
/// `NSTableView` addresses rows by a single index, so a grouped list has to be flattened
/// into one sequence. Every index-based behaviour in the List — selection, arrow keys,
/// drag-selection, scroll-to-row — is built on these indices, which is why the flattening
/// is a tested pure function rather than something computed inside the data source.
///
/// Only Duplicates uses headers. All Media stays a plain list of items, so its indices are
/// unchanged and none of the existing behaviour shifts.
enum MediaListRow: Equatable {
    case header(String)
    case item(String)

    var isHeader: Bool {
        if case .header = self { return true }
        return false
    }

    /// The media item's id, or `nil` for a header.
    var itemID: String? {
        if case let .item(id) = self { return id }
        return nil
    }

    /// Flattens duplicate groups into header-then-members order.
    static func rows(forGroups groups: [DuplicateGrouping.Group]) -> [MediaListRow] {
        groups.flatMap { group in
            [.header(group.title)] + group.members.map { .item($0.file.id) }
        }
    }

    /// The row an item occupies, counting the headers above it.
    static func rowIndex(ofItemID id: String, in rows: [MediaListRow]) -> Int? {
        rows.firstIndex { $0.itemID == id }
    }
}
