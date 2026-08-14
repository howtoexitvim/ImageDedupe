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
    /// The List's intrinsic content width now comes from the table's own columns rather
    /// than from a viewport formula. Anything narrower scrolls horizontally.
    static var minimumContentWidth: Double {
        Double(MediaTableColumn.totalDefaultWidth)
    }

    static func contentWidth(viewportWidth: Double) -> Double {
        max(viewportWidth, minimumContentWidth)
    }
}

struct ThumbnailCell: View {
    let image: NSImage?
    let side: Double
    let isImported: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            if isImported {
                ImportedBadge()
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: side, height: side)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct ImportedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white, Color.green)
            .shadow(radius: 1)
            .help("Imported")
    }
}
