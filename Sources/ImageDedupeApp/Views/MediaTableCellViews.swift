import AppKit

/// Reusable cell views for the native List.
///
/// Each cell fills its column with autoresizing rather than a hard-coded frame, so column
/// resize is handled entirely by `NSTableView`.

@MainActor
final class MediaTextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(identifier: NSUserInterfaceItemIdentifier, alignment: NSTextAlignment) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = alignment
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

@MainActor
final class MediaCheckboxCellView: NSTableCellView {
    private let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var onToggle: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        button.target = self
        button.action = #selector(toggle)
        // The table itself owns keyboard focus; Space toggles the focused row. Excluding
        // row checkboxes from Tab order keeps large catalogs navigable with FKA while
        // preserving each checkbox as a VoiceOver-accessible action.
        button.refusesFirstResponder = true
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(isChecked: Bool, name: String, onToggle: @escaping () -> Void) {
        setChecked(isChecked)
        button.setAccessibilityLabel("Select \(name)")
        self.onToggle = onToggle
    }

    /// Updates only the checked state, for live refreshes that must not rebind the action.
    func setChecked(_ isChecked: Bool) {
        button.state = isChecked ? .on : .off
    }

    @objc private func toggle() {
        onToggle?()
    }
}

@MainActor
final class MediaThumbnailCellView: NSTableCellView {
    private let thumbnail = NSImageView()
    private let importedBadge = NSImageView()
    private let duplicateBadge = NSImageView()
    private var sideConstraints: [NSLayoutConstraint] = []

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 3
        thumbnail.layer?.masksToBounds = true
        thumbnail.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)
        imageView = thumbnail

        importedBadge.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Imported")
        importedBadge.contentTintColor = .systemGreen
        importedBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(importedBadge)

        duplicateBadge.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Duplicate candidate")
        duplicateBadge.contentTintColor = .systemOrange
        duplicateBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(duplicateBadge)

        NSLayoutConstraint.activate([
            thumbnail.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            importedBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 2),
            importedBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 2),
            importedBadge.widthAnchor.constraint(equalToConstant: 12),
            importedBadge.heightAnchor.constraint(equalToConstant: 12),
            duplicateBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: -2),
            duplicateBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: -2),
            duplicateBadge.widthAnchor.constraint(equalToConstant: 12),
            duplicateBadge.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(
        image: NSImage?,
        side: CGFloat,
        isImported: Bool,
        isDuplicateCandidate: Bool,
        isKeptCopy: Bool = false
    ) {
        thumbnail.image = image ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "No preview yet")
        importedBadge.isHidden = !isImported

        // The same two meanings as the Grid tile, so a duplicate group reads identically in
        // either view: blue seal for the copy that survives, orange triangle for the copies
        // Delete would remove. One badge view, so the row gains no extra layout.
        if isKeptCopy {
            duplicateBadge.image = NSImage(
                systemSymbolName: "checkmark.seal.fill",
                accessibilityDescription: "Kept copy"
            )
            duplicateBadge.contentTintColor = .systemBlue
            duplicateBadge.toolTip = "This copy is kept."
            duplicateBadge.isHidden = false
        } else {
            duplicateBadge.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Duplicate candidate"
            )
            duplicateBadge.contentTintColor = .systemOrange
            duplicateBadge.toolTip = "A duplicate of a copy kept elsewhere."
            duplicateBadge.isHidden = !isDuplicateCandidate
        }

        NSLayoutConstraint.deactivate(sideConstraints)
        sideConstraints = [
            thumbnail.widthAnchor.constraint(equalToConstant: side),
            thumbnail.heightAnchor.constraint(equalToConstant: side)
        ]
        NSLayoutConstraint.activate(sideConstraints)
    }
}
