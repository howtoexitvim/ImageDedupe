import DeduperCore
import SwiftUI

struct MediaBrowserView: View {
    @StateObject private var viewModel = MediaBrowserViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
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
        } detail: {
            InspectorView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        }
    }

    private var sidebar: some View {
        List(selection: .constant("iphone")) {
            Section("Devices") {
                Label(viewModel.deviceName, systemImage: "iphone")
                    .tag("iphone")
            }
            Section("Review") {
                Label("All Media", systemImage: "photo.on.rectangle")
                Label("Duplicates", systemImage: "rectangle.on.rectangle")
                    .badge(viewModel.duplicatePlan.delete.count)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.scan()
            } label: {
                Label(viewModel.isScanning ? "Scanning..." : "Scan iPhone", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isScanning)
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("View", selection: $viewModel.viewMode) {
                Label("List", systemImage: "list.bullet").tag(MediaBrowserViewModel.ViewMode.list)
                Label("Grid", systemImage: "square.grid.3x3").tag(MediaBrowserViewModel.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Divider().frame(height: 22)

            Picker("Kind", selection: $viewModel.selectedKind) {
                ForEach(viewModel.kinds, id: \.self) { kind in
                    Text(kind).tag(kind)
                }
            }
            .frame(width: 110)

            Picker("Sort", selection: $viewModel.sortField) {
                Text("Name").tag(MediaSortField.name)
                Text("Kind").tag(MediaSortField.kind)
                Text("Date").tag(MediaSortField.timestamp)
                Text("Size").tag(MediaSortField.size)
            }
            .frame(width: 110)

            Picker("Order", selection: $viewModel.sortOrder) {
                Text("Asc").tag(SortOrder.ascending)
                Text("Desc").tag(SortOrder.descending)
            }
            .frame(width: 90)

            Spacer()

            TextField("Search name", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.status)
                .lineLimit(1)
            Spacer()
            Text("\(viewModel.filteredItems.count) shown / \(viewModel.allItems.count) total")
            Text("Would delete \(viewModel.duplicatePlan.delete.count)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
