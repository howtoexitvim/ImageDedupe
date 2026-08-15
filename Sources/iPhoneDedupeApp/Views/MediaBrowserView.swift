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
                if let advice = viewModel.recoveryAdvice {
                    RecoveryBanner(
                        advice: advice,
                        onRetry: {
                            viewModel.dismissRecoveryAdvice()
                            viewModel.scan()
                        },
                        onDismiss: { viewModel.dismissRecoveryAdvice() }
                    )
                }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.reconcileImportedDownloads()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaResetLayout)) { _ in
            panePreferences.reset()
            columnVisibility = .all
        }
        .sheet(isPresented: $viewModel.isShowingOperationHistory) {
            OperationHistoryView(
                records: viewModel.operationHistory,
                warning: viewModel.operationHistoryWarning,
                onRetryVerification: { viewModel.retryDeleteVerification(recordID: $0) },
                onClear: { viewModel.clearOperationHistory() },
                onDone: { viewModel.isShowingOperationHistory = false }
            )
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
        .onChange(of: sidebarSelection) { _, selection in
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
                Label("List", systemImage: "list.bullet")
                    .accessibilityLabel("List view")
                    .tag(MediaBrowserViewModel.ViewMode.list)
                Label("Grid", systemImage: "square.grid.3x3")
                    .accessibilityLabel("Grid view")
                    .tag(MediaBrowserViewModel.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .help("View mode")
            .accessibilityLabel("View mode")
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
                .accessibilityLabel("Thumbnail size")
                Image(systemName: "photo.fill")
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.toggleInspector()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(viewModel.isInspectorVisible ? "Hide inspector" : "Show inspector")
            .accessibilityLabel(viewModel.isInspectorVisible ? "Hide inspector" : "Show inspector")
        }
    }

    /// Fixed single-line bottom bar.
    ///
    /// The height is driven by the content's natural single-line height; `GeometryReader`
    /// only measures the available width so `MediaStatusBarLayout` can decide which labels
    /// survive. Nothing here is allowed to wrap.
    private var statusBar: some View {
        GeometryReader { proxy in
            statusBarContent(
                plan: MediaStatusBarLayout.plan(
                    availableWidth: proxy.size.width,
                    hasProgress: viewModel.operationProgress != nil
                )
            )
            // The height is clamped on the content, not just on the GeometryReader. The
            // reader reports the width it is offered, which can briefly exceed what the
            // content actually gets; clamping only the outer frame let a label wrap inside
            // and push the bar to two lines anyway.
            .frame(
                width: proxy.size.width,
                height: statusBarHeight,
                alignment: .leading
            )
            .clipped()
        }
        .frame(height: statusBarHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One line of caption text plus the vertical padding, so the bar cannot change height.
    /// Derived from the font rather than hardcoded, so larger accessibility text still fits
    /// instead of clipping the controls.
    private var statusBarHeight: CGFloat {
        let lineHeight = NSFont.preferredFont(forTextStyle: .caption1).boundingRectForFont.height
        return max(28, ceil(lineHeight) + 20)
    }

    private func statusBarContent(plan: MediaStatusBarLayout.Plan) -> some View {
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
                if plan.showsDestinationTitle {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(viewModel.importDestination.lastPathComponent)
                            .mediaStatusBarLabel()
                    }
                } else {
                    // Collapses to the icon rather than wrapping the folder name.
                    Image(systemName: "folder")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Download destination: \(viewModel.importDestination.path)")
            .accessibilityLabel("Download destination: \(viewModel.importDestination.lastPathComponent)")

            Button {
                viewModel.importSelected()
            } label: {
                if plan.showsActionTitles {
                    Text("Download").mediaStatusBarLabel()
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .fixedSize()
            .disabled(viewModel.selectedActionIDs.isEmpty || viewModel.isDeviceBusy)
            .help("Download the selected items")
            .accessibilityLabel("Download")

            Button {
                viewModel.revealLastImportInFinder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal last imported file in Finder")
            .accessibilityLabel("Reveal last imported file in Finder")

            Button {
                viewModel.requestDeleteConfirmation()
            } label: {
                if plan.showsActionTitles {
                    Text("Delete").mediaStatusBarLabel()
                } else {
                    Image(systemName: "trash")
                }
            }
            .fixedSize()
            .disabled(viewModel.selectedActionIDs.isEmpty || viewModel.isDeviceBusy)
            .help("Delete the selected items from the iPhone")
            .accessibilityLabel("Delete")

            Divider().frame(height: 16)

            if !viewModel.operationHistory.isEmpty || viewModel.operationHistoryWarning != nil {
                Button {
                    viewModel.showOperationHistory()
                } label: {
                    if plan.showsResultsTitle {
                        // `Label` lets its title wrap inside a borderless button, which is
                        // how this became `Re-/sults` and grew the bar. An explicit HStack
                        // of icon + non-wrapping Text does not.
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle")
                            Text("Results").mediaStatusBarLabel()
                        }
                    } else {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Review saved import and delete issues")
                .accessibilityLabel("Review saved operation results")
            }

            if let progress = viewModel.operationProgress {
                if plan.showsProgressBar {
                    ProgressView(value: progress.fractionCompleted)
                        .frame(width: 96)
                        .accessibilityLabel(progress.kind == .importing ? "Import progress" : "Delete progress")
                        .accessibilityValue("\(progress.completedItems) of \(progress.totalItems)")
                }
                Text(progress.detail)
                    .mediaStatusBarText(
                        MediaStatusBarText(message: progress.detail, prefix: "Operation status")
                    )
                Button {
                    viewModel.cancelCurrentOperation()
                } label: {
                    if plan.showsActionTitles {
                        Text(progress.isCanceling ? "Canceling…" : "Cancel")
                            .mediaStatusBarLabel()
                    } else {
                        // Never truncate this one to `...`; it is the control the user needs
                        // most while an operation is running.
                        Image(systemName: "xmark.circle")
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(!progress.canCancel)
                .help(progress.isCanceling ? "Canceling…" : "Cancel the current operation")
                .accessibilityLabel(progress.isCanceling ? "Canceling" : "Cancel")
                .accessibilityHint("Stops after the device acknowledges cancellation")
            } else {
                Text(viewModel.status)
                    .mediaStatusBarText(MediaStatusBarText(message: viewModel.status))
            }
            // Guarantees breathing room between Cancel and the counts even when the bar is
            // tight; a plain Spacer collapses to zero and lets them touch.
            Spacer(minLength: 16)
            HStack(spacing: 12) {
                if plan.showsSelectedCount {
                    Text("\(viewModel.selectedActionIDs.count) selected")
                        .mediaStatusBarLabel()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Selected items: \(viewModel.selectedActionIDs.count)")
                }
                if plan.showsShownCount {
                    Text("\(viewModel.filteredItems.count) shown / \(viewModel.allItems.count) total")
                        .mediaStatusBarLabel()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Shown items: \(viewModel.filteredItems.count) of \(viewModel.allItems.count)")
                }
                if plan.showsDuplicateCount {
                    Text("Duplicate candidates \(viewModel.duplicatePlan.delete.count)")
                        .mediaStatusBarLabel()
                        .foregroundStyle(.secondary)
                        .help("Conservative duplicate candidates under the current name-kind-size rule.")
                        .accessibilityLabel("Duplicate candidates: \(viewModel.duplicatePlan.delete.count)")
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
        // The structural guarantee. `fixedSize(horizontal:)` tells SwiftUI it may not
        // resolve a too-narrow bar by wrapping text; combined with the fixed height on the
        // container, content that does not fit is clipped and dropped by
        // `MediaStatusBarLayout` instead of pushing the bar to a second line.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxHeight: statusBarHeight)
        .clipped()
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            "Delete \(viewModel.pendingDeleteSnapshot?.items.count ?? 0) item(s) from this iPhone?",
            isPresented: $viewModel.isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete From Device", role: .destructive) {
                viewModel.deleteSelected()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteConfirmation()
            }
        } message: {
            Text("\(ByteCountFormatter.string(fromByteCount: viewModel.pendingDeleteSnapshot?.totalBytes ?? 0, countStyle: .file)) will be submitted to ImageCaptureCore device deletion and cannot be undone by this app.")
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
