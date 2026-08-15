import AppKit
import DeduperCore
import SwiftUI

/// Native List renderer.
///
/// Geometry ownership, per the layout incident's permanent guardrails:
/// - `NSScrollView` owns the document size, both scrollers, and the clip origin.
/// - `NSTableView` owns row frames, the header, and column widths.
/// - Nothing here reads sidebar widths, window width, or inspector visibility.
///
/// The SwiftUI wrapper only pushes data and pulls intent.
struct MediaTableView: NSViewRepresentable {
    @ObservedObject var viewModel: MediaBrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = MediaNativeTableView()
        tableView.coordinator = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        // Action selection is our own concept; AppKit's row selection would be a second,
        // conflicting source of truth.
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .plain
        tableView.rowSizeStyle = .custom
        tableView.headerView = NSTableHeaderView()
        // `.noColumnAutoresizing` rather than `.lastColumnOnlyAutoresizingStyle`.
        //
        // With last-column autoresizing, AppKit shrinks columns to fit the viewport instead
        // of letting the table overflow. In a narrow center pane that compressed the
        // leading checkbox/thumbnail/name columns out of view with nothing to scroll to,
        // because the document never became wider than the clip view. Keeping the columns
        // at their own widths is what makes the horizontal scroller real.
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        // Native header drag reordering. The checkbox and thumbnail columns opt out below.
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true

        let preferences = context.coordinator.preferences
        for column in preferences.columnOrder {
            let tableColumn = NSTableColumn(identifier: column.userInterfaceIdentifier)
            tableColumn.title = column.title
            tableColumn.width = preferences.width(for: column)
            tableColumn.minWidth = column.minimumWidth
            tableColumn.maxWidth = column.maximumWidth
            // User resizing only. Autoresizing would let AppKit shrink a column below the
            // width the user chose in order to fit a narrow viewport.
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
        }

        // Persist user-driven resize and reorder.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.columnGeometryDidChange),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.columnGeometryDidChange),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.resetLayoutRequested),
            name: .mediaResetLayout,
            object: nil
        )

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        // The table's own width decides whether horizontal scrolling is needed. Letting
        // the scroll view stretch the document would hide real overflow.
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.apply(items: viewModel.filteredItems)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var viewModel: MediaBrowserViewModel
        let controller: MediaTableController
        weak var scrollView: NSScrollView?
        weak var tableView: NSTableView?

        private var items: [MediaBrowserViewModel.MediaItem] = []
        private var lastRenderKey: RenderKey?

        /// The inputs that actually change what a row draws. Comparing this avoids a full
        /// `reloadData` on every SwiftUI update pass.
        private struct RenderKey: Equatable {
            let ids: [String]
            let actionSelected: Set<String>
            let focused: String?
            let imported: Set<String>
            let thumbnailSide: Double
            let thumbnailCount: Int
            let sortField: MediaSortField
            let sortOrder: DeduperCore.SortOrder
        }

        let preferences: MediaColumnPreferences

        init(viewModel: MediaBrowserViewModel, preferences: MediaColumnPreferences = MediaColumnPreferences()) {
            self.viewModel = viewModel
            self.controller = MediaTableController(viewModel: viewModel)
            self.preferences = preferences
            super.init()
            // Restore the persisted sort before the first snapshot is published.
            viewModel.applySort(field: preferences.sortField, order: preferences.sortOrder)
            viewModel.onSortChanged = { [weak preferences] field, order in
                preferences?.setSort(field: field, order: order)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Saves column widths and order after a native resize or header drag.
        @objc func columnGeometryDidChange(_ notification: Notification) {
            guard let tableView else { return }
            var order: [MediaTableColumn] = []
            for tableColumn in tableView.tableColumns {
                guard let column = MediaTableColumn.column(for: tableColumn.identifier) else { continue }
                order.append(column)
                preferences.setWidth(tableColumn.width, for: column)
            }
            preferences.setColumnOrder(order)
        }

        @objc func resetLayoutRequested() {
            resetLayout()
        }

        /// Restores the declared layout and persists the reset.
        func resetLayout() {
            preferences.reset()
            guard let tableView else { return }

            for (index, column) in MediaTableColumn.allCases.enumerated() {
                guard let currentIndex = tableView.tableColumns.firstIndex(where: {
                    MediaTableColumn.column(for: $0.identifier) == column
                }) else { continue }
                if currentIndex != index {
                    tableView.moveColumn(currentIndex, toColumn: index)
                }
            }
            for tableColumn in tableView.tableColumns {
                guard let column = MediaTableColumn.column(for: tableColumn.identifier) else { continue }
                tableColumn.width = column.defaultWidth
            }
            viewModel.applySort(
                field: MediaColumnPreferences.defaultSortField,
                order: MediaColumnPreferences.defaultSortOrder
            )
        }

        func apply(items: [MediaBrowserViewModel.MediaItem]) {
            let key = RenderKey(
                ids: items.map(\.id),
                actionSelected: viewModel.selectedActionIDs,
                focused: viewModel.selectedItemID,
                imported: viewModel.importedItemIDs,
                thumbnailSide: viewModel.displayScale.listThumbnailSide,
                thumbnailCount: viewModel.thumbnailCache.count,
                sortField: viewModel.sortField,
                sortOrder: viewModel.sortOrder
            )
            guard key != lastRenderKey else { return }

            let rowsChanged = lastRenderKey?.ids != key.ids
            let heightChanged = lastRenderKey?.thumbnailSide != key.thumbnailSide
            lastRenderKey = key
            self.items = items

            guard let tableView else { return }
            updateSortIndicator(on: tableView)
            if rowsChanged || heightChanged {
                tableView.reloadData()
            } else {
                let columns = IndexSet(integersIn: 0..<tableView.numberOfColumns)
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<items.count), columnIndexes: columns)
            }
            if heightChanged {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<items.count))
            }
        }

        private func updateSortIndicator(on tableView: NSTableView) {
            for tableColumn in tableView.tableColumns {
                guard let column = MediaTableColumn.column(for: tableColumn.identifier) else { continue }
                if column.sortField == viewModel.sortField {
                    tableView.setIndicatorImage(
                        NSImage(named: viewModel.sortOrder == .ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"),
                        in: tableColumn
                    )
                } else {
                    tableView.setIndicatorImage(nil, in: tableColumn)
                }
            }
        }

        // MARK: - Context menu

        /// Builds the row context menu. Delete only *requests* confirmation; it never
        /// invokes the device delete directly.
        func contextMenu(forRow row: Int) -> NSMenu? {
            guard items.indices.contains(row) else { return nil }
            let item = items[row]
            viewModel.prepareContextActionSelection(for: item)

            let menu = NSMenu()
            let label = viewModel.selectedActionIDs.count > 1
                ? "\(viewModel.selectedActionIDs.count) Items"
                : "\u{201C}\(item.model.name)\u{201D}"

            let select = NSMenuItem(title: "Select", action: #selector(toggleSelectionFromMenu), keyEquivalent: "")
            select.target = self
            select.representedObject = item.id
            menu.addItem(select)
            menu.addItem(.separator())

            let importItem = NSMenuItem(title: "Import \(label)", action: #selector(importFromMenu), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)

            let deleteItem = NSMenuItem(title: "Delete \(label)", action: #selector(requestDeleteFromMenu), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)

            return menu
        }

        @objc private func toggleSelectionFromMenu(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let item = items.first(where: { $0.id == id }) else { return }
            viewModel.toggleActionSelection(item)
        }

        @objc private func importFromMenu() {
            viewModel.importSelected()
        }

        @objc private func requestDeleteFromMenu() {
            viewModel.requestDeleteConfirmation()
        }

        /// Scrolls the focused row into view after keyboard movement, keeping a row of
        /// context around it.
        ///
        /// `scrollRowToVisible` alone scrolls the minimum distance, parking the focused row
        /// flush against the edge with nothing visible beyond it, which reads as the list
        /// not scrolling at all.
        func scrollFocusIntoView() {
            guard let tableView,
                  let clipView = scrollView?.contentView,
                  let focusedID = viewModel.selectedItemID,
                  let row = controller.row(for: focusedID),
                  row >= 0, row < tableView.numberOfRows else { return }

            let rowRect = tableView.rect(ofRow: row)
            guard let origin = MediaScrollGeometry.originToRevealItem(
                rowRect,
                in: clipView.documentVisibleRect
            ) else { return }

            let maxOrigin = max(0, tableView.bounds.height - clipView.bounds.height)
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: min(origin, maxOrigin)))
            scrollView?.reflectScrolledClipView(clipView)
        }

        /// Repaints focus and action-selection decoration on the rows that are on screen.
        ///
        /// Row views cache their state, so moving focus with the keyboard has to push the
        /// new values into the live views. Without this the highlight stays on the row
        /// where the last click happened and the user loses track of focus.
        func refreshFocusDecoration() {
            guard let tableView else { return }
            let isBrowserFocused = viewModel.selection.focusOwner == .mediaBrowser
            let focusedID = viewModel.selectedItemID
            let actionSelected = viewModel.selectedActionIDs

            for row in visibleRowRange(in: tableView) {
                guard items.indices.contains(row),
                      let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? MediaTableRowView else { continue }
                let id = items[row].id
                rowView.isFocusedItem = focusedID == id
                rowView.isActionSelected = actionSelected.contains(id)
                rowView.isBrowserFocused = isBrowserFocused

                // The checkbox lives in a cell view, so it needs the new value too.
                if let cell = tableView.view(
                    atColumn: tableView.column(withIdentifier: MediaTableColumn.selection.userInterfaceIdentifier),
                    row: row,
                    makeIfNecessary: false
                ) as? MediaCheckboxCellView {
                    cell.setChecked(actionSelected.contains(id))
                }
            }
        }

        private func visibleRowRange(in tableView: NSTableView) -> Range<Int> {
            let rows = tableView.rows(in: tableView.visibleRect)
            guard rows.length > 0 else { return 0..<0 }
            let lower = max(0, rows.location)
            let upper = min(items.count, rows.location + rows.length)
            guard lower < upper else { return 0..<0 }
            return lower..<upper
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            MediaTableMetrics.rowHeight(thumbnailSide: viewModel.displayScale.listThumbnailSide)
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn,
                  let column = MediaTableColumn.column(for: tableColumn.identifier),
                  items.indices.contains(row) else { return nil }
            let item = items[row]
            viewModel.loadVisibleDetails(for: item)

            switch column {
            case .selection:
                return checkboxCell(for: item, tableView: tableView)
            case .thumbnail:
                return thumbnailCell(for: item, tableView: tableView)
            default:
                return textCell(column: column, item: item, tableView: tableView)
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = MediaTableRowView()
            if items.indices.contains(row) {
                let item = items[row]
                rowView.isActionSelected = viewModel.selectedActionIDs.contains(item.id)
                rowView.isFocusedItem = viewModel.selectedItemID == item.id
                rowView.isBrowserFocused = viewModel.selection.focusOwner == .mediaBrowser
                rowView.accessibilityDescription = MediaAccessibilityLabel.describe(
                    item.model,
                    isSelected: viewModel.selectedActionIDs.contains(item.id),
                    isImported: viewModel.importedItemIDs.contains(item.id),
                    isDuplicateCandidate: viewModel.duplicateDeleteIDs.contains(item.id)
                )
            }
            return rowView
        }

        /// Header clicks drive our own sort model rather than AppKit's descriptors, so
        /// sorting stays the domain layer's job.
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let column = MediaTableColumn.column(for: tableColumn.identifier),
                  let field = column.sortField else { return }
            viewModel.toggleSort(field)
        }

        func selectionShouldChange(in tableView: NSTableView) -> Bool {
            false
        }

        /// The checkbox and thumbnail columns are row furniture, not data. Keeping them
        /// pinned to the leading edge is what stops a header drag from putting the
        /// checkbox in the middle of the row.
        func tableView(
            _ tableView: NSTableView,
            shouldReorderColumn columnIndex: Int,
            toColumn newColumnIndex: Int
        ) -> Bool {
            guard let moved = column(at: columnIndex, in: tableView) else { return false }
            guard moved.isReorderable else { return false }
            // Nor may a data column be dragged in front of the pinned ones.
            let pinnedCount = tableView.tableColumns.prefix { column(at: $0, in: tableView)?.isReorderable == false }.count
            return newColumnIndex >= pinnedCount
        }

        private func column(at index: Int, in tableView: NSTableView) -> MediaTableColumn? {
            guard tableView.tableColumns.indices.contains(index) else { return nil }
            return MediaTableColumn.column(for: tableView.tableColumns[index].identifier)
        }

        private func column(at tableColumn: NSTableColumn, in tableView: NSTableView) -> MediaTableColumn? {
            MediaTableColumn.column(for: tableColumn.identifier)
        }

        // MARK: - Cells

        private func checkboxCell(for item: MediaBrowserViewModel.MediaItem, tableView: NSTableView) -> NSView {
            let identifier = MediaTableColumn.selection.userInterfaceIdentifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? MediaCheckboxCellView
                ?? MediaCheckboxCellView(identifier: identifier)
            cell.configure(isChecked: viewModel.selectedActionIDs.contains(item.id), name: item.model.name) { [weak self] in
                self?.viewModel.toggleActionSelection(item)
            }
            return cell
        }

        private func thumbnailCell(for item: MediaBrowserViewModel.MediaItem, tableView: NSTableView) -> NSView {
            let identifier = MediaTableColumn.thumbnail.userInterfaceIdentifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? MediaThumbnailCellView
                ?? MediaThumbnailCellView(identifier: identifier)
            cell.configure(
                image: viewModel.thumbnailCache[item.id],
                side: CGFloat(viewModel.displayScale.listThumbnailSide),
                isImported: viewModel.importedItemIDs.contains(item.id),
                isDuplicateCandidate: viewModel.duplicateDeleteIDs.contains(item.id)
            )
            return cell
        }

        private func textCell(column: MediaTableColumn, item: MediaBrowserViewModel.MediaItem, tableView: NSTableView) -> NSView {
            let identifier = column.userInterfaceIdentifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? MediaTextCellView
                ?? MediaTextCellView(identifier: identifier, alignment: column.alignment)
            cell.stringValue = MediaTableText.value(for: column, item: item.model)
            return cell
        }
    }
}

/// Formats a domain value for one column. Kept free of AppKit so it stays unit-testable.
enum MediaTableText {
    /// Uses the user's real locale and time zone; the tests inject their own.
    private static let format = MediaDisplayFormat()

    static func value(for column: MediaTableColumn, item: DeviceMediaFile) -> String {
        let format = Self.format
        switch column {
        case .selection, .thumbnail:
            return ""
        case .name:
            return item.name
        case .kind:
            return item.kind
        case .timestamp:
            return format.timestamp(item.timestamp) ?? ""
        case .size:
            return format.fileSize(item.size)
        case .duration:
            return format.duration(item.duration) ?? ""
        }
    }
}
