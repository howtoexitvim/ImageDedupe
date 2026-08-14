import SwiftUI

struct MediaGridView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel
    @State private var isConfirmingDelete = false

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: viewModel.displayScale.gridMinimumSide,
                    maximum: viewModel.displayScale.gridMaximumSide
                ),
                spacing: 10
            )
        ]
    }

    var body: some View {
        gridBody
            // The Grid is still the SwiftUI renderer until Phase 4, so it has no native
            // first responder to claim focus ownership. Without this the shared model
            // never sees `.mediaBrowser` and Escape silently does nothing here, even
            // though it works in the List.
            .onAppear { viewModel.setFocusOwner(.mediaBrowser) }
            .onExitCommand { viewModel.clearSelection() }
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.filteredItems) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            ThumbnailTile(
                                image: viewModel.thumbnailCache[item.id],
                                height: viewModel.displayScale.gridThumbnailHeight
                            )
                            HStack(spacing: 4) {
                                if viewModel.duplicateDeleteIDs.contains(item.id) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                                if viewModel.importedItemIDs.contains(item.id) {
                                    ImportedBadge()
                                }
                                Button {
                                    viewModel.toggleActionSelection(item)
                                } label: {
                                    Image(systemName: viewModel.selectedActionIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(viewModel.selectedActionIDs.contains(item.id) ? Color.accentColor : Color.white.opacity(0.88))
                                        .shadow(radius: 1)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(5)
                        }
                        Text(item.model.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(selectionBackground(for: item), in: RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { viewModel.select(item) }
                    .onAppear { viewModel.loadVisibleDetails(for: item) }
                    .contextMenu {
                        Button("Select") {
                            viewModel.toggleActionSelection(item)
                        }
                        Divider()
                        Button("Import \(actionLabel(for: item))") {
                            viewModel.prepareContextActionSelection(for: item)
                            viewModel.importSelected()
                        }
                        Button("Delete \(actionLabel(for: item))", role: .destructive) {
                            viewModel.prepareContextActionSelection(for: item)
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .padding(12)
        }
        .confirmationDialog(
            "Delete \(viewModel.selectedActionIDs.count) item(s) from this iPhone?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete From Device", role: .destructive) {
                viewModel.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone by this app.")
        }
    }

    private func selectionBackground(for item: MediaBrowserViewModel.MediaItem) -> Color {
        if viewModel.selectedActionIDs.contains(item.id) {
            return Color.accentColor.opacity(0.24)
        }
        return item.id == viewModel.selectedItemID ? Color.accentColor.opacity(0.18) : Color.clear
    }

    private func actionLabel(for item: MediaBrowserViewModel.MediaItem) -> String {
        if viewModel.selectedActionIDs.count > 1 {
            return "\(viewModel.selectedActionIDs.count) Items"
        }
        return "\"\(item.model.name)\""
    }
}

struct ThumbnailTile: View {
    let image: NSImage?
    let height: Double

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
