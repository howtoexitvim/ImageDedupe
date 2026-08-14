import AppKit
import DeduperCore

/// Contact-sheet geometry for the Grid.
///
/// This is deliberately a separate type from `MediaTableColumn`. A table and a contact
/// sheet have different geometry, scrolling, and selection semantics; sharing one layout
/// object between them is what caused the 2026-08-15 regression. They share the selection
/// model, not the renderer.
enum MediaGridLayout {
    static let spacing: CGFloat = 10
    static let sectionInset: CGFloat = 12

    /// Vertical room a tile needs below its thumbnail for the name and size labels.
    static let captionHeight: CGFloat = 34

    /// Horizontal padding inside a tile, around the thumbnail.
    static let tilePadding: CGFloat = 6

    /// How many whole items fit across `availableWidth`.
    ///
    /// Always at least one: a viewport narrower than a single item still shows that item
    /// and scrolls, rather than computing a zero or negative column count.
    static func columnCount(
        availableWidth: CGFloat,
        itemWidth: CGFloat,
        spacing: CGFloat = spacing,
        sectionInset: CGFloat = sectionInset
    ) -> Int {
        let contentWidth = availableWidth - sectionInset * 2
        guard contentWidth > 0, itemWidth > 0 else { return 1 }

        // n items need n*itemWidth + (n-1)*spacing.
        let count = Int(floor((contentWidth + spacing) / (itemWidth + spacing)))
        return max(1, count)
    }

    /// The fixed size of one tile at the current thumbnail density.
    ///
    /// Item size is fixed rather than stretched to fill the row. `LazyVGrid`'s adaptive
    /// sizing let items grow independently of their content, which is what produced the
    /// reported overlapping tiles.
    static func itemSize(thumbnailHeight: Double) -> NSSize {
        let side = CGFloat(thumbnailHeight)
        return NSSize(
            width: side + tilePadding * 2,
            height: side + captionHeight + tilePadding * 2
        )
    }

    static func itemSize(for scale: MediaDisplayScale) -> NSSize {
        itemSize(thumbnailHeight: scale.gridThumbnailHeight)
    }

    /// The column count the Grid currently shows, used for Up/Down navigation so keyboard
    /// movement matches what the user actually sees.
    static func columnCount(availableWidth: CGFloat, scale: MediaDisplayScale) -> Int {
        columnCount(availableWidth: availableWidth, itemWidth: itemSize(for: scale).width)
    }
}
