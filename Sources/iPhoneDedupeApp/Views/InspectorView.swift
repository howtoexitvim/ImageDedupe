import DeduperCore
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
        .task(id: viewModel.selectedItemID) {
            if let item = viewModel.selectedItem {
                viewModel.loadInspectorPreview(for: item)
            } else {
                viewModel.clearInspectorPreviewSelection()
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
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func preview(for item: MediaBrowserViewModel.MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image = viewModel.inspectorPreviewImage(for: item) {
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
                .minimumScaleFactor(0.85)

            if viewModel.duplicateDeleteIDs.contains(item.id) {
                Label("Conservative duplicate candidate", systemImage: "rectangle.on.rectangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(14)
    }

    /// The user's real locale and time zone.
    private let format = MediaDisplayFormat()

    private func metadata(for item: MediaBrowserViewModel.MediaItem) -> some View {
        let metadata = viewModel.metadataSummary(for: item)
        return List {
            Section("Metadata") {
                row("Kind", item.model.kind)
                row("Size", format.fileSize(item.model.size))
                row("Timestamp", format.timestamp(item.model.timestamp) ?? "Unknown")
                row("Width", item.model.width.map(String.init) ?? "Unknown")
                row("Height", item.model.height.map(String.init) ?? "Unknown")
                row("Location", metadata?.location ?? item.model.location ?? "Loading")
                row("Aperture", metadata?.aperture ?? "Loading")
                row("Color Space", metadata?.colorSpace ?? "Loading")
                row("Shutter", metadata?.shutterSpeed ?? "Loading")
                row("Maker", metadata?.maker ?? "Loading")
                row("Model", metadata?.model ?? "Loading")
                row("Duration", format.duration(item.model.duration) ?? "Unknown")
                row("RAW", item.model.isRaw ? "Yes" : "No")
                row("High FPS", item.model.isHighFramerate ? "Yes" : "No")
                row("Time Lapse", item.model.isTimeLapse ? "Yes" : "No")
                row("Group UUID", item.model.groupUUID ?? "Unknown")
                row("Burst UUID", item.model.burstUUID ?? "Unknown")
            }
            Section("Duplicate Dry Run") {
                row("Rule", "name-kind-size")
                row("Duplicate candidates", "\(viewModel.duplicatePlan.delete.count)")
                row("Estimated space", ByteCountFormatter.string(fromByteCount: viewModel.duplicateBytes, countStyle: .file))
                Text("Deletion requires explicit confirmation.")
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
                .lineLimit(2)
        }
    }

    private func durationText(_ duration: Double?) -> String {
        guard let duration else {
            return "Unknown"
        }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
