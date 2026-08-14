import DeduperCore
import SwiftUI

struct MediaBrowserView: View {
    @StateObject private var viewModel = MediaBrowserViewModel()
    private let autoScanOnLaunch: Bool

    init(autoScanOnLaunch: Bool = false) {
        self.autoScanOnLaunch = autoScanOnLaunch
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 270)
        } content: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if viewModel.viewMode == .list {
                    MediaListView(viewModel: viewModel)
                } else {
                    MediaGridView(viewModel: viewModel)
                }
                Divider()
                statusBar
            }
            .navigationSplitViewColumnWidth(min: 680, ideal: 860)
        } detail: {
            InspectorView(viewModel: viewModel)
                .frame(minWidth: 320, idealWidth: 340, maxWidth: 380, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 320, ideal: 340, max: 380)
        }
        .task {
            if autoScanOnLaunch {
                viewModel.scan()
            }
        }
    }

    private var sidebar: some View {
        List(selection: .constant("iphone")) {
            Section("Devices") {
                Label(viewModel.deviceName, systemImage: "iphone")
                    .lineLimit(1)
                    .tag("iphone")
            }
            Section("Review") {
                Label("All Media", systemImage: "photo.on.rectangle")
                    .lineLimit(1)
                Label("Duplicates", systemImage: "rectangle.on.rectangle")
                    .lineLimit(1)
                    .badge(viewModel.duplicatePlan.delete.count)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.scan()
            } label: {
                Label(viewModel.isScanning ? "Scanning..." : "Scan iPhone", systemImage: "arrow.clockwise")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isScanning)
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("View")
                .foregroundStyle(.secondary)
            Picker("View", selection: $viewModel.viewMode) {
                Label("List", systemImage: "list.bullet").tag(MediaBrowserViewModel.ViewMode.list)
                Label("Grid", systemImage: "square.grid.3x3").tag(MediaBrowserViewModel.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)

            Divider().frame(height: 22)

            Text("Kind")
                .foregroundStyle(.secondary)
            Picker("Kind", selection: $viewModel.selectedKind) {
                ForEach(viewModel.kinds, id: \.self) { kind in
                    Text(kind).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 116)

            Text("Sort")
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $viewModel.sortField) {
                Text("Name").tag(MediaSortField.name)
                Text("Kind").tag(MediaSortField.kind)
                Text("Date").tag(MediaSortField.timestamp)
                Text("Size").tag(MediaSortField.size)
            }
            .labelsHidden()
            .frame(width: 116)

            Text("Order")
                .foregroundStyle(.secondary)
            Picker("Order", selection: $viewModel.sortOrder) {
                Text("Asc").tag(SortOrder.ascending)
                Text("Desc").tag(SortOrder.descending)
            }
            .labelsHidden()
            .frame(width: 112)

            Spacer(minLength: 12)

            TextField("Search name", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)
                .layoutPriority(1)

            Divider().frame(height: 22)

            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { viewModel.displayScale.value },
                    set: { viewModel.setDisplayScale($0) }
                ),
                in: 0.75...1.6
            )
            .frame(width: 120)
            Image(systemName: "photo.fill")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.status)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Text("\(viewModel.filteredItems.count) shown / \(viewModel.allItems.count) total")
                .lineLimit(1)
            Text("Would delete \(viewModel.duplicatePlan.delete.count)")
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
