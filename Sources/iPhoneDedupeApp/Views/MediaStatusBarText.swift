import SwiftUI

/// Layout contract for the status bar's one variable-length label.
///
/// A long idle message such as "Delete finished, but verification is pending…" used to wrap
/// and grow the bottom bar vertically. The label is now bounded horizontally and clipped to
/// one line, with the full text preserved for Help and VoiceOver. The bar keeps its natural
/// single-line height rather than a magic fixed height, so larger accessibility text sizes
/// still lay out without clipping the controls.
struct MediaStatusBarText: Equatable {
    enum Truncation: Equatable {
        case tail
    }

    let message: String
    let prefix: String

    /// Wide enough to stay useful, bounded so the selected/shown/duplicate counts on the
    /// trailing edge are never pushed out of the bar.
    let minimumWidth: CGFloat = 80
    let maximumWidth: CGFloat? = 320

    let lineLimit: Int = 1
    let truncation: Truncation = .tail

    init(message: String, prefix: String = "Status") {
        self.message = message
        self.prefix = prefix
    }

    /// The untruncated message, so hovering recovers whatever the ellipsis hid.
    var help: String { message }

    var accessibilityLabel: String { "\(prefix): \(message)" }
}

extension View {
    /// Applies the bounded single-line status contract to a status/progress label.
    func mediaStatusBarText(_ label: MediaStatusBarText) -> some View {
        self
            .lineLimit(label.lineLimit)
            .truncationMode(.tail)
            .frame(
                minWidth: label.minimumWidth,
                idealWidth: label.maximumWidth,
                maxWidth: label.maximumWidth,
                alignment: .leading
            )
            .fixedSize(horizontal: false, vertical: true)
            .help(label.help)
            .accessibilityLabel(label.accessibilityLabel)
    }
}
