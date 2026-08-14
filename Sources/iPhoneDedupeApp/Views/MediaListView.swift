import SwiftUI

struct MediaListView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel

    var body: some View {
        Table(viewModel.filteredItems, selection: $viewModel.selectedItemID) {
            TableColumn("") { item in
                ThumbnailCell(image: viewModel.thumbnailCache[item.id])
                    .onAppear { viewModel.loadThumbnails(for: [item]) }
            }
            .width(44)

            TableColumn("Name") { item in
                HStack {
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
            }
            .width(min: 220, ideal: 320)

            TableColumn("Kind") { item in
                Text(item.model.kind)
            }
            .width(70)

            TableColumn("Date") { item in
                Text(item.model.timestamp ?? "")
                    .lineLimit(1)
            }
            .width(min: 160, ideal: 210)

            TableColumn("Size") { item in
                Text(ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file))
            }
            .width(90)
        }
        .onChange(of: viewModel.selectedItemID) { newValue in
            guard let id = newValue,
                  let item = viewModel.allItems.first(where: { $0.id == id }) else {
                return
            }
            viewModel.select(item)
        }
    }
}

struct ThumbnailCell: View {
    let image: NSImage?

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
        .frame(width: 32, height: 32)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
