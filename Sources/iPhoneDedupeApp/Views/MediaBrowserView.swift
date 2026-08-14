import DeduperCore
import AppKit
import SwiftUI

struct MediaBrowserView: View {
    @StateObject private var viewModel = MediaBrowserViewModel()
    @State private var sidebarSelection: SidebarItem = .allMedia
    @State private var isConfirmingDelete = false
    private let autoScanOnLaunch: Bool

    private enum SidebarItem: String, Hashable {
        case device
        case allMedia
        case duplicates
    }

    init(autoScanOnLaunch: Bool = false) {
        self.autoScanOnLaunch = autoScanOnLaunch
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                toolbar
                    .frame(height: 52)
                    .zIndex(2)
                Divider()
                mediaContent
                Divider()
                statusBar
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            if viewModel.isInspectorVisible {
                Divider()
                InspectorView(viewModel: viewModel)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
        }
        .task {
            if autoScanOnLaunch {
                viewModel.scan()
            }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.viewMode == .list {
            MediaListView(viewModel: viewModel)
                .zIndex(0)
                .clipped()
        } else {
            MediaGridView(viewModel: viewModel)
                .zIndex(0)
                .clipped()
        }
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Devices") {
                Label(viewModel.deviceName, systemImage: "iphone")
                    .lineLimit(1)
                    .tag(SidebarItem.device)
            }
            Section("Review") {
                Label("All Media", systemImage: "photo.on.rectangle")
                    .lineLimit(1)
                    .tag(SidebarItem.allMedia)
                Label("Duplicates", systemImage: "rectangle.on.rectangle")
                    .lineLimit(1)
                    .badge(viewModel.duplicatePlan.delete.count)
                    .tag(SidebarItem.duplicates)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: sidebarSelection) { selection in
            switch selection {
            case .device, .allMedia:
                viewModel.selectReviewScope(.allMedia)
            case .duplicates:
                viewModel.selectReviewScope(.duplicates)
            }
        }
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
        HStack(spacing: 12) {
            Button {
                viewModel.toggleInspector()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .help(viewModel.isInspectorVisible ? "Hide inspector" : "Show inspector")

            Divider().frame(height: 24)

            Picker("View", selection: $viewModel.viewMode) {
                Label("List", systemImage: "list.bullet").tag(MediaBrowserViewModel.ViewMode.list)
                Label("Grid", systemImage: "square.grid.3x3").tag(MediaBrowserViewModel.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .help("View mode")

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search name, kind, size:>2mb, duration:<10s", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
            .frame(minWidth: 260, idealWidth: 420, maxWidth: 520)
            .help("Smart search: plain text or tokens like kind:heic size:>2mb duration:<10s")

            Divider().frame(height: 24)

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
            .help("Thumbnail size")
            Image(systemName: "photo.fill")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            Menu {
                destinationButton("Pictures", .picturesDirectory)
                destinationButton("Desktop", .desktopDirectory)
                destinationButton("Documents", .documentDirectory)
                destinationButton("Movies", .moviesDirectory)
                destinationButton("Downloads", .downloadsDirectory)
                Divider()
                Button("Other...") { chooseImportDestination() }
            } label: {
                Label(viewModel.importDestination.lastPathComponent, systemImage: "folder")
            }
            .menuStyle(.borderlessButton)

            Button("Import") {
                viewModel.importSelected()
            }
            .disabled(viewModel.selectedActionIDs.isEmpty)

            Button {
                viewModel.revealLastImportInFinder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal last imported file in Finder")

            Button("Delete") {
                isConfirmingDelete = true
            }
            .disabled(viewModel.selectedActionIDs.isEmpty)

            Divider().frame(height: 16)

            Text(viewModel.status)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Text("\(viewModel.selectedActionIDs.count) selected")
                .lineLimit(1)
            Text("\(viewModel.filteredItems.count) shown / \(viewModel.allItems.count) total")
                .lineLimit(1)
            Text("Would delete \(viewModel.duplicatePlan.delete.count)")
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            Text("This uses ImageCaptureCore device deletion and cannot be undone by this app.")
        }
    }

    private func destinationButton(_ title: String, _ directory: FileManager.SearchPathDirectory) -> some View {
        Button(title) {
            if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
                viewModel.importDestination = url
            }
        }
    }

    private func chooseImportDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.importDestination
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.importDestination = url
        }
    }
}
