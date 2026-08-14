import SwiftUI

/// Phase 4: the Grid is a native `NSCollectionView`. This wrapper contributes no geometry
/// of its own — it fills the center pane and lets the collection view's scroll view own
/// the document size and scroller.
struct MediaGridView: View {
    @ObservedObject var viewModel: MediaBrowserViewModel

    var body: some View {
        MediaCollectionView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
