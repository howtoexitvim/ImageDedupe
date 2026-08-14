import AppKit
import DeduperCore
import SwiftUI

struct MediaListView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                        row(for: item, index: index)
                            .onTapGesture { viewModel.select(item) }
                            .onAppear { viewModel.loadVisibleDetails(for: item) }
                    }
                }
            }
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

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.selectedActionIDs.count == viewModel.filteredItems.count {
                    viewModel.clearActionSelection()
                } else {
                    viewModel.selectAllVisible()
                }
            } label: {
                Image(systemName: viewModel.selectedActionIDs.isEmpty ? "square" : "checkmark.square")
            }
            .buttonStyle(.plain)
            .frame(width: 26)

            Spacer()
                .frame(width: viewModel.displayScale.listThumbnailSide + 8)

            headerCell("Name", field: .name)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            headerCell("Kind", field: .kind)
                .frame(width: 54, alignment: .leading)
            headerCell("Date", field: .timestamp)
                .frame(width: 190, alignment: .leading)
            headerCell("File Size", field: .size)
                .frame(width: 86, alignment: .trailing)
            headerCell("Duration", field: .duration)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func headerCell(_ title: String, field: MediaSortField) -> some View {
        Button {
            viewModel.toggleSort(field)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if field == viewModel.sortField {
                    Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }

    private func row(for item: MediaBrowserViewModel.MediaItem, index: Int) -> some View {
        let isActionSelected = viewModel.selectedActionIDs.contains(item.id)

        return HStack(spacing: 12) {
            Button {
                viewModel.toggleActionSelection(item)
            } label: {
                Image(systemName: isActionSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isActionSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 26)

            ThumbnailCell(
                image: viewModel.thumbnailCache[item.id],
                side: viewModel.displayScale.listThumbnailSide,
                isImported: viewModel.importedItemIDs.contains(item.id)
            )
            .frame(width: viewModel.displayScale.listThumbnailSide + 8)

            cellText(item.model.name)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            cellText(item.model.kind)
                .frame(width: 54, alignment: .leading)
            cellText(item.model.timestamp ?? "")
                .frame(width: 190, alignment: .leading)
            cellText(ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file))
                .frame(width: 86, alignment: .trailing)
            cellText(durationText(item.model.duration))
                .frame(width: 72, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: max(34, viewModel.displayScale.listThumbnailSide + 10))
        .background(rowBackground(for: item, index: index, isActionSelected: isActionSelected))
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

    private func cellText(_ value: String) -> some View {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
    }

    private func durationText(_ duration: Double?) -> String {
        guard let duration else { return "" }
        let totalSeconds = Int(duration.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func actionLabel(for item: MediaBrowserViewModel.MediaItem) -> String {
        if viewModel.selectedActionIDs.count > 1 {
            return "\(viewModel.selectedActionIDs.count) Items"
        }
        return "\"\(item.model.name)\""
    }

    private func rowBackground(for item: MediaBrowserViewModel.MediaItem, index: Int, isActionSelected: Bool) -> Color {
        if isActionSelected {
            return Color.accentColor.opacity(0.22)
        }
        if item.id == viewModel.selectedItemID {
            return Color.accentColor.opacity(0.12)
        }
        return index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06)
    }
}

struct ThumbnailCell: View {
    let image: NSImage?
    let side: Double
    let isImported: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            if isImported {
                ImportedBadge()
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: side, height: side)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct ImportedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white, Color.green)
            .shadow(radius: 1)
            .help("Imported")
    }
}
