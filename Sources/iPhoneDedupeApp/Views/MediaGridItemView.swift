import AppKit

/// One contact-sheet tile: thumbnail, badges, checkbox, name, and size.
///
/// Built in code rather than a nib so the whole Grid renderer stays reviewable in one
/// place. Sizes come from `MediaGridLayout`, never from the enclosing pane width.
@MainActor
final class MediaGridItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MediaGridItem")

    private let thumbnail = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let importedBadge = NSImageView()
    private let duplicateBadge = NSImageView()
    private let container = MediaGridTileView()

    private var onToggle: (() -> Void)?
    private var thumbnailHeightConstraint: NSLayoutConstraint!

    override func loadView() {
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        container.wantsLayer = true

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 5
        thumbnail.layer?.masksToBounds = true
        thumbnail.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(thumbnail)
        imageView = thumbnail

        nameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)
        textField = nameLabel

        sizeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.lineBreakMode = .byTruncatingTail
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sizeLabel)

        checkbox.target = self
        checkbox.action = #selector(toggleSelection)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checkbox)

        importedBadge.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Imported")
        importedBadge.contentTintColor = .systemGreen
        importedBadge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(importedBadge)

        duplicateBadge.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "Duplicate candidate"
        )
        duplicateBadge.contentTintColor = .systemOrange
        duplicateBadge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(duplicateBadge)

        // An image view with no height constraint takes its height from the image's
        // intrinsic size, so every photo produced a differently sized tile and the labels
        // collided. The thumbnail is pinned to an explicit square instead, and the labels
        // get fixed heights, so a tile's layout never depends on its content.
        let padding = MediaGridLayout.tilePadding
        thumbnailHeightConstraint = thumbnail.heightAnchor.constraint(equalToConstant: 0)
        thumbnail.setContentHuggingPriority(.defaultLow, for: .vertical)
        thumbnail.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            thumbnail.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            thumbnail.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            thumbnailHeightConstraint,

            nameLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor),
            nameLabel.heightAnchor.constraint(equalToConstant: MediaGridLayout.nameLabelHeight),

            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            sizeLabel.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor),
            sizeLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor),
            sizeLabel.heightAnchor.constraint(equalToConstant: MediaGridLayout.sizeLabelHeight),

            checkbox.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 4),
            checkbox.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -4),

            duplicateBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 4),
            duplicateBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 4),
            duplicateBadge.widthAnchor.constraint(equalToConstant: 14),
            duplicateBadge.heightAnchor.constraint(equalToConstant: 14),

            importedBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -4),
            importedBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -4),
            importedBadge.widthAnchor.constraint(equalToConstant: 14),
            importedBadge.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(
        name: String,
        size: String,
        thumbnailHeight: CGFloat,
        image: NSImage?,
        isActionSelected: Bool,
        isFocused: Bool,
        isBrowserFocused: Bool,
        isImported: Bool,
        isDuplicateCandidate: Bool,
        onToggle: @escaping () -> Void
    ) {
        thumbnailHeightConstraint.constant = thumbnailHeight
        nameLabel.stringValue = name
        sizeLabel.stringValue = size
        thumbnail.image = image ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "No preview yet")
        checkbox.state = isActionSelected ? .on : .off
        checkbox.setAccessibilityLabel("Select \(name)")
        importedBadge.isHidden = !isImported
        duplicateBadge.isHidden = !isDuplicateCandidate
        self.onToggle = onToggle

        container.isActionSelected = isActionSelected
        container.isFocusedItem = isFocused
        container.isBrowserFocused = isBrowserFocused
    }

    @objc private func toggleSelection() {
        onToggle?()
    }
}

/// Draws the tile's focus and action-selection states.
///
/// Focus and action selection stay visually distinct: an item can be focused without being
/// checked, and checked without being focused.
@MainActor
final class MediaGridTileView: NSView {
    var isActionSelected = false {
        didSet { if isActionSelected != oldValue { needsDisplay = true } }
    }

    var isFocusedItem = false {
        didSet { if isFocusedItem != oldValue { needsDisplay = true } }
    }

    var isBrowserFocused = false {
        didSet { if isBrowserFocused != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)

        if isActionSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
            rounded.fill()
        } else if isFocusedItem {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            rounded.fill()
        }

        if isFocusedItem {
            NSColor.controlAccentColor
                .withAlphaComponent(isBrowserFocused ? 0.9 : 0.4)
                .setStroke()
            rounded.lineWidth = isBrowserFocused ? 2 : 1
            rounded.stroke()
        }
    }
}
