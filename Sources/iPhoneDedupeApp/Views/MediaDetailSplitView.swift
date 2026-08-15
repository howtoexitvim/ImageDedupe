import AppKit
import SwiftUI

/// Hosts the center browser and the inspector in a native `NSSplitView`.
///
/// Why AppKit rather than an `HStack`:
///
/// - An `HStack` divider is decorative; only a split view gives a draggable divider with
///   the system resize cursor.
/// - When two `HStack` children both declare a minimum width and the space is short,
///   SwiftUI must violate one, and it clipped the browser's leading columns.
/// - Removing the inspector's minimum instead let the center's `maxWidth: .infinity`
///   collapse the inspector to nothing.
///
/// `NSSplitView` resolves both: it honours per-pane minimums via its delegate and holds the
/// divider position itself. The panes read their own bounds; nothing here computes a
/// document origin from a sibling's width.
struct MediaDetailSplitView<Content: View, Inspector: View>: NSViewRepresentable {
    let isInspectorVisible: Bool
    let inspectorWidth: CGFloat
    let onInspectorWidthChange: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let inspector: () -> Inspector

    func makeCoordinator() -> Coordinator {
        Coordinator(onInspectorWidthChange: onInspectorWidthChange)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let contentHost = NSHostingView(rootView: AnyView(content()))
        let inspectorHost = NSHostingView(rootView: AnyView(inspector()))
        context.coordinator.contentHost = contentHost
        context.coordinator.inspectorHost = inspectorHost

        splitView.addArrangedSubview(contentHost)
        splitView.addArrangedSubview(inspectorHost)
        context.coordinator.splitView = splitView

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.contentHost?.rootView = AnyView(content())
        context.coordinator.inspectorHost?.rootView = AnyView(inspector())
        context.coordinator.setInspectorVisible(isInspectorVisible, preferredWidth: inspectorWidth)
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        private let onInspectorWidthChange: (CGFloat) -> Void
        weak var splitView: NSSplitView?
        var contentHost: NSHostingView<AnyView>?
        var inspectorHost: NSHostingView<AnyView>?

        private var isInspectorVisible = true

        init(onInspectorWidthChange: @escaping (CGFloat) -> Void) {
            self.onInspectorWidthChange = onInspectorWidthChange
        }

        func setInspectorVisible(_ visible: Bool, preferredWidth: CGFloat) {
            guard let splitView, let inspectorHost else { return }
            let changed = visible != isInspectorVisible
            isInspectorVisible = visible

            inspectorHost.isHidden = !visible
            guard visible else {
                splitView.adjustSubviews()
                return
            }

            // Only drive the divider when the inspector is being revealed, so a later user
            // drag is not overwritten on every SwiftUI update pass.
            if changed {
                let target = max(0, splitView.bounds.width - preferredWidth - splitView.dividerThickness)
                splitView.setPosition(target, ofDividerAt: 0)
            }
        }

        // MARK: - NSSplitViewDelegate

        /// The center browser keeps its declared minimum; the divider cannot be dragged
        /// past it. This is the constraint the SwiftUI version could not express.
        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            max(proposedMinimumPosition, MediaPaneLayout.minimumCenterWidth)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            min(
                proposedMaximumPosition,
                splitView.bounds.width - MediaPane.inspector.minimumWidth - splitView.dividerThickness
            )
        }

        /// The center browser absorbs window resizing; the inspector holds its width.
        func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
            view === contentHost
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            subview === inspectorHost
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard isInspectorVisible,
                  let inspectorHost,
                  !inspectorHost.isHidden,
                  inspectorHost.bounds.width > 0 else { return }
            onInspectorWidthChange(inspectorHost.bounds.width)
        }
    }
}
