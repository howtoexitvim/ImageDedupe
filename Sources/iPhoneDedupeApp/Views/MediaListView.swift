import SwiftUI

struct MediaListView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel
    private let tableWidth: Double = 1760

    var body: some View {
        ScrollView(.horizontal) {
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
            .frame(width: tableWidth, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer()
                .frame(width: viewModel.displayScale.listThumbnailSide + 8)
            headerText("Name")
                .frame(width: 220, alignment: .leading)
            headerText("Kind")
                .frame(width: 72, alignment: .leading)
            headerText("Date")
                .frame(width: 190, alignment: .leading)
            headerText("File Size")
                .frame(width: 96, alignment: .trailing)
            headerText("Width")
                .frame(width: 70, alignment: .trailing)
            headerText("Height")
                .frame(width: 70, alignment: .trailing)
            headerText("Location")
                .frame(width: 190, alignment: .leading)
            headerText("Aperture")
                .frame(width: 80, alignment: .trailing)
            headerText("Color Space")
                .frame(width: 110, alignment: .leading)
            headerText("Shutter Speed")
                .frame(width: 120, alignment: .trailing)
            headerText("Maker")
                .frame(width: 100, alignment: .leading)
            headerText("Model")
                .frame(width: 120, alignment: .leading)
            headerText("Duration")
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .frame(width: tableWidth, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func row(for item: MediaBrowserViewModel.MediaItem, index: Int) -> some View {
        let metadata = viewModel.metadataSummary(for: item)
        return HStack(spacing: 12) {
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
            .frame(width: 220, alignment: .leading)

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

            Text(item.model.width.map(String.init) ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(item.model.height.map(String.init) ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(metadata?.location ?? item.model.location ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)

            Text(metadata?.aperture ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(metadata?.colorSpace ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(metadata?.shutterSpeed ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(metadata?.maker ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(metadata?.model ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(durationText(item.model.duration))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: max(34, viewModel.displayScale.listThumbnailSide + 10))
        .frame(width: tableWidth, alignment: .leading)
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

    private func durationText(_ duration: Double?) -> String {
        guard let duration else {
            return ""
        }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
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
