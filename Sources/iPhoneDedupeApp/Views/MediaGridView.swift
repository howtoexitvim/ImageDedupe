import AppKit
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

/// Retained for any SwiftUI surface that still shows a large thumbnail.
struct ThumbnailTile: View {
    let image: NSImage?
    let height: Double

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
