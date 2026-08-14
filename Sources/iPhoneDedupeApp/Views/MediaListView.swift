import AppKit
import DeduperCore
import SwiftUI

/// Phase 2: the List is a native `NSTableView`. This wrapper contributes no geometry of
/// its own — it fills the center pane and lets the table's scroll view own the document
/// size, scrollers, and clip origin.
struct MediaListView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel

    var body: some View {
        MediaTableView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MediaListLayout {
    /// The List's intrinsic content width comes from the table's own columns rather than
    /// from a viewport formula. Anything narrower scrolls horizontally.
    static var minimumContentWidth: Double {
        Double(MediaTableColumn.totalDefaultWidth)
    }

    static func contentWidth(viewportWidth: Double) -> Double {
        max(viewportWidth, minimumContentWidth)
    }
}
