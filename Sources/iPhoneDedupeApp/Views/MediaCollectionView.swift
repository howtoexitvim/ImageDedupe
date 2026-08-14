import AppKit
import DeduperCore
import SwiftUI

/// Native Grid renderer.
///
/// Geometry ownership mirrors the List: the `NSScrollView` owns the document size and
/// scrollers, and the flow layout sizes items from `MediaGridLayout` alone. Nothing here
/// reads sidebar widths or inspector visibility.
///
/// This is a separate renderer from the List by design. They share the selection model,
/// not layout objects.
struct MediaCollectionView: NSViewRepresentable {
    @ObservedObject var viewModel: MediaBrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = MediaGridLayout.spacing
        layout.minimumLineSpacing = MediaGridLayout.spacing
        layout.sectionInset = NSEdgeInsets(
            top: MediaGridLayout.sectionInset,
            left: MediaGridLayout.sectionInset,
            bottom: MediaGridLayout.sectionInset,
            right: MediaGridLayout.sectionInset
        )
        layout.itemSize = MediaGridLayout.itemSize(for: viewModel.displayScale)

        let collectionView = MediaNativeCollectionView()
        collectionView.coordinator = context.coordinator
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.controlBackgroundColor]
        collectionView.register(MediaGridItemView.self, forItemWithIdentifier: MediaGridItemView.identifier)

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        // The collection view must track the clip view's width so the flow layout reflows
        // on resize instead of keeping a stale row width.
        collectionView.autoresizingMask = [.width]

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.apply(items: viewModel.filteredItems)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var viewModel: MediaBrowserViewModel
        weak var collectionView: MediaNativeCollectionView?
        weak var scrollView: NSScrollView?

        private var items: [MediaBrowserViewModel.MediaItem] = []
        private var lastRenderKey: RenderKey?

        private struct RenderKey: Equatable {
            let ids: [String]
            let actionSelected: Set<String>
            let focused: String?
            let imported: Set<String>
            let thumbnailHeight: Double
            let thumbnailCount: Int
            let browserFocused: Bool
        }

        init(viewModel: MediaBrowserViewModel) {
            self.viewModel = viewModel
        }

        func apply(items: [MediaBrowserViewModel.MediaItem]) {
            let key = RenderKey(
                ids: items.map(\.id),
                actionSelected: viewModel.selectedActionIDs,
                focused: viewModel.selectedItemID,
                imported: viewModel.importedItemIDs,
                thumbnailHeight: viewModel.displayScale.gridThumbnailHeight,
                thumbnailCount: viewModel.thumbnailCache.count,
                browserFocused: viewModel.selection.focusOwner == .mediaBrowser
            )
            guard key != lastRenderKey else { return }

            let densityChanged = lastRenderKey?.thumbnailHeight != key.thumbnailHeight
            let itemsChanged = lastRenderKey?.ids != key.ids
            lastRenderKey = key
            self.items = items

            guard let collectionView else { return }

            if densityChanged, let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
                // A density change invalidates Grid layout only. It must not touch the
                // List's column preferences.
                layout.itemSize = MediaGridLayout.itemSize(for: viewModel.displayScale)
                layout.invalidateLayout()
            }

            if itemsChanged || densityChanged {
                // A density change also reloads so every live item picks up the new
                // thumbnail height; the layout was invalidated just above.
                collectionView.reloadData()
            } else {
                refreshVisibleDecoration()
            }
        }

        /// The column count the user can actually see, used for Up/Down navigation.
        var currentColumnCount: Int {
            guard let collectionView else { return 1 }
            return MediaGridLayout.columnCount(
                availableWidth: collectionView.bounds.width,
                scale: viewModel.displayScale
            )
        }

        func scrollFocusIntoView() {
            guard let collectionView,
                  let focusedID = viewModel.selectedItemID,
                  let index = items.firstIndex(where: { $0.id == focusedID }) else { return }
            collectionView.scrollToItems(
                at: [IndexPath(item: index, section: 0)],
                scrollPosition: .nearestHorizontalEdge
            )
        }

        /// Pushes current focus/selection into the live item views without a full reload.
        func refreshVisibleDecoration() {
            guard let collectionView else { return }
            let isBrowserFocused = viewModel.selection.focusOwner == .mediaBrowser
            let focusedID = viewModel.selectedItemID
            let actionSelected = viewModel.selectedActionIDs

            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard items.indices.contains(indexPath.item),
                      let item = collectionView.item(at: indexPath) as? MediaGridItemView else { continue }
                configure(item, at: indexPath.item, focusedID: focusedID, actionSelected: actionSelected, isBrowserFocused: isBrowserFocused)
            }
        }

        private func configure(
            _ view: MediaGridItemView,
            at index: Int,
            focusedID: String?,
            actionSelected: Set<String>,
            isBrowserFocused: Bool
        ) {
            let item = items[index]
            viewModel.loadVisibleDetails(for: item)
            view.configure(
                name: item.model.name,
                size: ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file),
                thumbnailHeight: CGFloat(viewModel.displayScale.gridThumbnailHeight).rounded(),
                image: viewModel.thumbnailCache[item.id],
                isActionSelected: actionSelected.contains(item.id),
                isFocused: focusedID == item.id,
                isBrowserFocused: isBrowserFocused,
                isImported: viewModel.importedItemIDs.contains(item.id),
                isDuplicateCandidate: viewModel.duplicateDeleteIDs.contains(item.id),
                onToggle: { [weak self] in
                    self?.viewModel.toggleActionSelection(item)
                    self?.refreshVisibleDecoration()
                }
            )
        }

        // MARK: - Interaction

        func itemID(at index: Int) -> String? {
            items.indices.contains(index) ? items[index].id : nil
        }

        func index(at point: NSPoint) -> Int? {
            guard let collectionView,
                  let indexPath = collectionView.indexPathForItem(at: point) else { return nil }
            return indexPath.item
        }

        func click(index: Int, modifiers: MediaTableController.Modifiers) {
            guard let id = itemID(at: index) else { return }
            if modifiers.contains(.shift) {
                viewModel.extendSelection(to: id)
            } else if modifiers.contains(.command) {
                viewModel.toggleActionSelection(withID: id)
            } else {
                viewModel.selectItem(withID: id)
            }
            refreshVisibleDecoration()
        }

        func doubleClick(index: Int) {
            guard let id = itemID(at: index) else { return }
            viewModel.selectItem(withID: id)
            viewModel.toggleActionSelection(withID: id)
            refreshVisibleDecoration()
        }

        /// Builds the item context menu. Delete only requests confirmation.
        func contextMenu(forIndex index: Int) -> NSMenu? {
            guard items.indices.contains(index) else { return nil }
            let item = items[index]
            viewModel.prepareContextActionSelection(for: item)

            let menu = NSMenu()
            let label = viewModel.selectedActionIDs.count > 1
                ? "\(viewModel.selectedActionIDs.count) Items"
                : "\u{201C}\(item.model.name)\u{201D}"

            let select = NSMenuItem(title: "Select", action: #selector(toggleFromMenu), keyEquivalent: "")
            select.target = self
            select.representedObject = item.id
            menu.addItem(select)
            menu.addItem(.separator())

            let importItem = NSMenuItem(title: "Import \(label)", action: #selector(importFromMenu), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)

            let deleteItem = NSMenuItem(title: "Delete \(label)", action: #selector(deleteFromMenu), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
            return menu
        }

        @objc private func toggleFromMenu(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            viewModel.toggleActionSelection(withID: id)
            refreshVisibleDecoration()
        }

        @objc private func importFromMenu() {
            viewModel.importSelected()
        }

        @objc private func deleteFromMenu() {
            viewModel.requestDeleteConfirmation()
        }

        // MARK: - NSCollectionViewDataSource

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let view = collectionView.makeItem(withIdentifier: MediaGridItemView.identifier, for: indexPath)
            guard let gridItem = view as? MediaGridItemView, items.indices.contains(indexPath.item) else {
                return view
            }
            configure(
                gridItem,
                at: indexPath.item,
                focusedID: viewModel.selectedItemID,
                actionSelected: viewModel.selectedActionIDs,
                isBrowserFocused: viewModel.selection.focusOwner == .mediaBrowser
            )
            return gridItem
        }
    }
}
