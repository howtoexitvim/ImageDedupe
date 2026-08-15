import AppKit

/// A duplicate group's header row: a checkbox that selects the whole group, and the
/// group's title.
///
/// The checkbox exists because a group can hold several copies, and ticking each one is
/// exactly the per-file tedium the grouped view was introduced to remove. It selects the
/// group's *redundant* copies only — never the copy being kept, so "select this group" can
/// never come to mean "delete every copy of this file".
final class MediaGroupHeaderCellView: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private var onToggle: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        checkbox.target = self
        checkbox.action = #selector(toggle)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isChecked: Bool, onToggle: @escaping () -> Void) {
        titleLabel.stringValue = title
        toolTip = title
        checkbox.state = isChecked ? .on : .off
        checkbox.setAccessibilityLabel("Select all duplicates in \(title)")
        self.onToggle = onToggle
    }

    @objc private func toggle() {
        onToggle?()
    }
}
