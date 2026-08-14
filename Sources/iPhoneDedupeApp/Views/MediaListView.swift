import SwiftUI

struct MediaListView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                        row(for: item, index: index)
                            .onTapGesture { viewModel.select(item) }
                            .onAppear { viewModel.loadThumbnails(for: [item]) }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer()
                .frame(width: viewModel.displayScale.listThumbnailSide + 8)
            headerText("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            headerText("Kind")
                .frame(width: 72, alignment: .leading)
            headerText("Date")
                .frame(width: 190, alignment: .leading)
            headerText("Size")
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func row(for item: MediaBrowserViewModel.MediaItem, index: Int) -> some View {
        HStack(spacing: 12) {
            ThumbnailCell(image: viewModel.thumbnailCache[item.id], side: viewModel.displayScale.listThumbnailSide)
                .frame(width: viewModel.displayScale.listThumbnailSide + 8)

            HStack(spacing: 6) {
                Text(item.model.name)
                    .lineLimit(1)
                if viewModel.duplicateDeleteIDs.contains(item.id) {
                    Text("duplicate")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.model.kind)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            Text(item.model.timestamp ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)

            Text(ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file))
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: max(34, viewModel.displayScale.listThumbnailSide + 10))
        .background(rowBackground(for: item, index: index))
    }

    private func headerText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func rowBackground(for item: MediaBrowserViewModel.MediaItem, index: Int) -> Color {
        if item.id == viewModel.selectedItemID {
            return Color.accentColor.opacity(0.18)
        }
        return index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06)
    }
}

struct ThumbnailCell: View {
    let image: NSImage?
    let side: Double

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
