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

/// Which bottom-bar elements fit at a given width.
///
/// The bar must never grow taller. Bounding the status label alone was not enough: at
/// narrow widths SwiftUI compressed the *other* labels instead, wrapping `Results` into
/// `Re-/sults` and pushing the bar to two lines. Every label therefore has a fixed
/// single-line size, and when the total no longer fits, whole elements are dropped in
/// priority order rather than being squeezed.
///
/// Controls the user must be able to press — the destination menu, Download, Delete,
/// Results, Cancel — always remain; only their text labels and the decorative progress bar
/// are dropped, leaving icons behind.
enum MediaStatusBarLayout {
    struct Plan: Equatable {
        var showsDestinationTitle = true
        var showsResultsTitle = true
        var showsProgressBar = true
        var showsProgressText = true
        var showsSelectedCount = true
        var showsShownCount = true
        var showsDuplicateCount = true

        /// Whether Download/Delete show their words or collapse to icons.
        ///
        /// A truncated button reading `D` is useless. Below this width they become
        /// recognizable icons with the full name in Help and VoiceOver.
        var showsActionTitles = true
    }

    /// Width the always-present controls need: destination icon, Download, reveal, Delete,
    /// divider, and the Results icon.
    ///
    /// Deliberately generous. These are measured-by-eye upper bounds, and under-estimating
    /// means labels stay in place and get compressed, which is the failure being prevented.
    private static let controlsWidth: CGFloat = 380

    /// The text each droppable element actually renders, so its width can be measured
    /// rather than guessed.
    struct Labels: Equatable {
        var duplicateCount: String
        var shownCount: String
        var selectedCount: String
        var destinationTitle: String
        var resultsTitle: String
        var progressText: String

        init(
            duplicateCount: String = "",
            shownCount: String = "",
            selectedCount: String = "",
            destinationTitle: String = "",
            resultsTitle: String = "",
            progressText: String = ""
        ) {
            self.duplicateCount = duplicateCount
            self.shownCount = shownCount
            self.selectedCount = selectedCount
            self.destinationTitle = destinationTitle
            self.resultsTitle = resultsTitle
            self.progressText = progressText
        }
    }

    /// Padding around a measured label: the spacing between status bar elements, which the
    /// string itself does not account for.
    private static let labelPadding: CGFloat = 16

    /// The rendered width of `text` in the status bar's font.
    ///
    /// Replaces hand-measured constants. Those were fixed numbers for text whose width
    /// depends on the system font and on the actual values shown — "4,000 duplicates ·
    /// 12.3 GB" is far wider than "2 duplicates · 900 KB" — so the drop points could fire
    /// early or late. One text layout per element per resize is not a cost worth guessing
    /// to avoid.
    static func measuredWidth(of text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return size.width.rounded(.up) + labelPadding
    }

    /// The progress bar is a fixed-size control, not text, so it keeps a constant.
    private static let progressBarWidth: CGFloat = 104

    /// Extra width the Download/Delete words occupy beyond their icons.
    private static let actionTitlesWidth: CGFloat = 110

    /// Chooses what the status bar can show in `availableWidth`.
    ///
    /// Elements are given up least-informative first: the counts are recoverable elsewhere
    /// in the UI, whereas the current operation's text is the one thing the user is waiting
    /// to read. Download and Delete keep their words longest, and collapse to icons rather
    /// than truncating to an unreadable `D`.
    static func plan(
        availableWidth: CGFloat,
        hasProgress: Bool,
        labels: Labels = Labels()
    ) -> Plan {
        var plan = Plan()

        let duplicateCountWidth = measuredWidth(of: labels.duplicateCount)
        let shownCountWidth = measuredWidth(of: labels.shownCount)
        let selectedCountWidth = measuredWidth(of: labels.selectedCount)
        let destinationTitleWidth = measuredWidth(of: labels.destinationTitle)
        let resultsTitleWidth = measuredWidth(of: labels.resultsTitle)
        let progressTextWidth = measuredWidth(of: labels.progressText)

        var required = controlsWidth
            + duplicateCountWidth
            + shownCountWidth
            + selectedCountWidth
            + destinationTitleWidth
            + resultsTitleWidth
        if hasProgress {
            plan.showsProgressBar = true
            required += progressBarWidth + progressTextWidth
        } else {
            plan.showsProgressBar = false
            plan.showsProgressText = false
        }

        func dropIfNeeded(_ width: CGFloat, _ drop: (inout Plan) -> Void) {
            guard required > availableWidth else { return }
            drop(&plan)
            required -= width
        }

        dropIfNeeded(duplicateCountWidth) { $0.showsDuplicateCount = false }
        dropIfNeeded(shownCountWidth) { $0.showsShownCount = false }
        dropIfNeeded(destinationTitleWidth) { $0.showsDestinationTitle = false }
        dropIfNeeded(resultsTitleWidth) { $0.showsResultsTitle = false }
        dropIfNeeded(selectedCountWidth) { $0.showsSelectedCount = false }
        if hasProgress {
            dropIfNeeded(progressBarWidth) { $0.showsProgressBar = false }
        }
        // Last resort, and only because an icon-only button still works while a button
        // reading `D` does not.
        dropIfNeeded(actionTitlesWidth) { $0.showsActionTitles = false }
        return plan
    }
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
            .help(label.help)
            .accessibilityLabel(label.accessibilityLabel)
    }

    /// Pins a bottom-bar label to exactly one line at its natural width.
    ///
    /// Without this, SwiftUI resolves a too-narrow bar by wrapping these labels — which is
    /// how `Results` became `Re-/sults` and made the bar two lines tall. `fixedSize` refuses
    /// the compression, and `MediaStatusBarLayout` removes whole elements instead.
    func mediaStatusBarLabel() -> some View {
        self
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
    }
}
