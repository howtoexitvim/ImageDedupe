import SwiftUI

struct InspectorView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = viewModel.selectedItem {
                preview(for: item)
                Divider()
                metadata(for: item)
            } else {
                emptySelection
            }
        }
    }

    private var emptySelection: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Selection")
                .font(.headline)
            Text("Select a media item to inspect it.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func preview(for item: MediaBrowserViewModel.MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image = viewModel.thumbnailCache[item.id] {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(item.model.name)
                .font(.headline)
                .lineLimit(2)

            if viewModel.duplicateDeleteIDs.contains(item.id) {
                Label("Conservative duplicate candidate", systemImage: "rectangle.on.rectangle")
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
    }

    private func metadata(for item: MediaBrowserViewModel.MediaItem) -> some View {
        List {
            Section("Metadata") {
                row("Kind", item.model.kind)
                row("Size", ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file))
                row("Timestamp", item.model.timestamp ?? "Unknown")
                row("Width", item.model.width.map(String.init) ?? "Unknown")
                row("Height", item.model.height.map(String.init) ?? "Unknown")
            }
            Section("Duplicate Dry Run") {
                row("Rule", "name-kind-size")
                row("Would delete", "\(viewModel.duplicatePlan.delete.count)")
                row("Estimated space", ByteCountFormatter.string(fromByteCount: viewModel.duplicateBytes, countStyle: .file))
                Text("Deletion is disabled in v0.1 UI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
