import AppKit
import DeduperCore
import SwiftUI

struct MediaListView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel
    @State private var columns = MediaListColumn.defaultOrder
    @State private var draggedColumn: MediaListColumn?
    @State private var isConfirmingDelete = false

    private var tableWidth: Double {
        92 + columns.reduce(0) { $0 + $1.width + 12 } + 24
    }

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

            ForEach(columns) { column in
                headerCell(for: column)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .frame(width: tableWidth, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func headerCell(for column: MediaListColumn) -> some View {
        Button {
            if let sortField = column.sortField {
                viewModel.toggleSort(sortField)
            }
        } label: {
            HStack(spacing: 4) {
                Text(column.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if column.sortField == viewModel.sortField {
                    Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundStyle(column.sortField == nil ? .secondary : .primary)
            .frame(width: column.width, alignment: column.alignment)
        }
        .buttonStyle(.plain)
        .disabled(column.sortField == nil)
        .onDrag {
            draggedColumn = column
            return NSItemProvider(object: column.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: ColumnDropDelegate(target: column, columns: $columns, draggedColumn: $draggedColumn))
        .help(column.sortField == nil ? "Metadata column" : "Sort by \(column.title). Drag to reorder columns.")
    }

    private func row(for item: MediaBrowserViewModel.MediaItem, index: Int) -> some View {
        let metadata = viewModel.metadataSummary(for: item)
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

            ThumbnailCell(image: viewModel.thumbnailCache[item.id], side: viewModel.displayScale.listThumbnailSide)
                .frame(width: viewModel.displayScale.listThumbnailSide + 8)

            ForEach(columns) { column in
                cellText(column.text(for: item, metadata: metadata))
                    .frame(width: column.width, alignment: column.alignment)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: max(34, viewModel.displayScale.listThumbnailSide + 10))
        .frame(width: tableWidth, alignment: .leading)
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
            .foregroundStyle(.secondary)
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

private enum MediaListColumn: String, CaseIterable, Identifiable, Equatable {
    case name
    case kind
    case date
    case fileSize
    case width
    case height
    case location
    case aperture
    case colorSpace
    case shutterSpeed
    case maker
    case model
    case duration

    var id: String { rawValue }

    static let defaultOrder: [MediaListColumn] = [
        .name, .kind, .date, .fileSize, .width, .height, .location, .aperture, .colorSpace, .shutterSpeed, .maker, .model, .duration
    ]

    var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .date: return "Date"
        case .fileSize: return "File Size"
        case .width: return "Width"
        case .height: return "Height"
        case .location: return "Location"
        case .aperture: return "Aperture"
        case .colorSpace: return "Color Space"
        case .shutterSpeed: return "Shutter Speed"
        case .maker: return "Maker"
        case .model: return "Model"
        case .duration: return "Duration"
        }
    }

    var width: Double {
        switch self {
        case .name: return 220
        case .kind: return 72
        case .date: return 190
        case .fileSize: return 96
        case .width, .height: return 70
        case .location: return 190
        case .aperture: return 80
        case .colorSpace: return 110
        case .shutterSpeed: return 120
        case .maker: return 100
        case .model: return 120
        case .duration: return 84
        }
    }

    var alignment: Alignment {
        switch self {
        case .fileSize, .width, .height, .aperture, .shutterSpeed, .duration:
            return .trailing
        default:
            return .leading
        }
    }

    var sortField: MediaSortField? {
        switch self {
        case .name: return .name
        case .kind: return .kind
        case .date: return .timestamp
        case .fileSize: return .size
        case .width: return .width
        case .height: return .height
        case .duration: return .duration
        case .location, .aperture, .colorSpace, .shutterSpeed, .maker, .model:
            return nil
        }
    }

    func text(for item: MediaBrowserViewModel.MediaItem, metadata: MediaMetadataSummary?) -> String {
        switch self {
        case .name: return item.model.name
        case .kind: return item.model.kind
        case .date: return item.model.timestamp ?? ""
        case .fileSize: return ByteCountFormatter.string(fromByteCount: item.model.size, countStyle: .file)
        case .width: return item.model.width.map(String.init) ?? ""
        case .height: return item.model.height.map(String.init) ?? ""
        case .location: return metadata?.location ?? item.model.location ?? ""
        case .aperture: return metadata?.aperture ?? ""
        case .colorSpace: return metadata?.colorSpace ?? ""
        case .shutterSpeed: return metadata?.shutterSpeed ?? ""
        case .maker: return metadata?.maker ?? ""
        case .model: return metadata?.model ?? ""
        case .duration: return durationText(item.model.duration)
        }
    }

    private func durationText(_ duration: Double?) -> String {
        guard let duration else { return "" }
        let totalSeconds = Int(duration.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

private struct ColumnDropDelegate: DropDelegate {
    let target: MediaListColumn
    @Binding var columns: [MediaListColumn]
    @Binding var draggedColumn: MediaListColumn?

    func dropEntered(info: DropInfo) {
        guard let draggedColumn,
              draggedColumn != target,
              let from = columns.firstIndex(of: draggedColumn),
              let to = columns.firstIndex(of: target) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.12)) {
            columns.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedColumn = nil
        return true
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
