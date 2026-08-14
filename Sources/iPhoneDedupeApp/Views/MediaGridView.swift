import SwiftUI

struct MediaGridView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel

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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.filteredItems) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            ThumbnailTile(
                                image: viewModel.thumbnailCache[item.id],
                                height: viewModel.displayScale.gridThumbnailHeight
                            )
                            if viewModel.duplicateDeleteIDs.contains(item.id) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .padding(5)
                            }
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
                    .onAppear { viewModel.loadThumbnails(for: [item]) }
                }
            }
            .padding(12)
        }
    }

    private func selectionBackground(for item: MediaBrowserViewModel.MediaItem) -> Color {
        item.id == viewModel.selectedItemID ? Color.accentColor.opacity(0.18) : Color.clear
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
