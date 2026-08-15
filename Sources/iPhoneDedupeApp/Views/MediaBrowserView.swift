import DeduperCore
import AppKit
import SwiftUI

struct MediaBrowserView: View {
    @StateObject private var viewModel = MediaBrowserViewModel()
    @State private var sidebarSelection: SidebarItem = .allMedia
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    private let panePreferences = MediaPanePreferences()
    private let autoScanOnLaunch: Bool

    private enum SidebarItem: String, Hashable {
        case device
        case allMedia
        case duplicates
    }

    init(autoScanOnLaunch: Bool = false) {
        self.autoScanOnLaunch = autoScanOnLaunch
    }

    /// Native split view.
    ///
    /// The toolbar is hosted by the window rather than by the center column. That is the
    /// structural fix for the toolbar overlapping the sidebar: it now spans the full window
    /// width above the split view and does not compete with pane geometry. The previous
    /// composition drew the toolbar inside the center `VStack` with `zIndex(2)` while the
    /// sidebar was a fixed-width sibling in an `HStack`, which produced the visible seam.
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: MediaPane.sidebar.minimumWidth,
                    ideal: paneWidth(.sidebar),
                    max: MediaPane.sidebar.maximumWidth
                )
        } detail: {
            VStack(spacing: 0) {
                mediaContent
                Divider()
                statusBar
            }
            .frame(minWidth: MediaPaneLayout.minimumCenterWidth, maxHeight: .infinity)
            // SwiftUI's own inspector, not a hand-rolled split view.
            //
            // Three earlier attempts failed here. An `HStack` has only a decorative
            // divider, and with both children declaring a minimum width SwiftUI clipped
            // the browser's leading columns. Dropping the inspector's minimum let the
            // center's infinite maxWidth squeeze it to nothing. Hosting an `NSSplitView`
            // myself rendered blank, because `NSHostingView`s added as arranged subviews
            // get neither a frame nor constraints and lay out at zero size.
            //
            // `.inspector` is the platform's answer: a real resizable trailing pane with a
            // draggable divider, whose width AppKit manages.
            .inspector(isPresented: $viewModel.isInspectorVisible) {
                InspectorView(viewModel: viewModel)
                    .inspectorColumnWidth(
                        min: MediaPane.inspector.minimumWidth,
                        ideal: paneWidth(.inspector),
                        max: MediaPane.inspector.maximumWidth
                    )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .task {
            if autoScanOnLaunch {
                viewModel.scan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaResetLayout)) { _ in
            panePreferences.reset()
            columnVisibility = .all
        }
    }

    private func paneWidth(_ pane: MediaPane) -> CGFloat {
        panePreferences.width(for: pane)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.viewMode == .list {
            MediaListView(viewModel: viewModel)
                .clipped()
        } else {
            MediaGridView(viewModel: viewModel)
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

    /// Window-hosted toolbar. Living in the titlebar area is what keeps it from overlapping
    /// the sidebar; it must not be reintroduced into the center column.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker(
                "View",
                selection: Binding(
                    get: { viewModel.viewMode },
                    set: { viewModel.setViewMode($0) }
                )
            ) {
                Label("List", systemImage: "list.bullet").tag(MediaBrowserViewModel.ViewMode.list)
                Label("Grid", systemImage: "square.grid.3x3").tag(MediaBrowserViewModel.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .help("View mode")
        }

        ToolbarItem(placement: .principal) {
            NativeSearchField(
                text: $viewModel.searchText,
                placeholder: "Name, or kind:heic size:>2mb duration:<10s",
                onFocusChange: { hasFocus in
                    // While the search field edits text, media shortcuts must not fire.
                    viewModel.setFocusOwner(hasFocus ? .search : .none)
                }
            )
            .frame(height: 28)
            .frame(minWidth: 220, idealWidth: 360, maxWidth: 520)
            .help("Type a filename, or use prefixes: name: kind: size: duration:. Text with no prefix searches the name.")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { viewModel.displayScale.value },
                        set: { viewModel.setDisplayScale($0) }
                    ),
                    in: 0.75...1.6
                )
                .frame(width: 110)
                .help("Thumbnail size")
                Image(systemName: "photo.fill")
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.toggleInspector()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(viewModel.isInspectorVisible ? "Hide inspector" : "Show inspector")
        }
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
                viewModel.requestDeleteConfirmation()
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
            Text("Duplicate candidates \(viewModel.duplicatePlan.delete.count)")
                .lineLimit(1)
                .help("Conservative duplicate candidates under the current name-kind-size rule.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .confirmationDialog(
            "Delete \(viewModel.selectedActionIDs.count) item(s) from this iPhone?",
            isPresented: $viewModel.isConfirmingDelete,
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
