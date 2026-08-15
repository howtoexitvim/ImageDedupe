import DeduperCore
import SwiftUI

/// Shows what went wrong with the device and what to do about it.
///
/// The status bar truncates and is easy to miss — a locked iPhone used to read as a broken
/// app. This sits above the browser with the numbered steps visible, and stays until the
/// user dismisses it or a scan succeeds.
struct RecoveryBanner: View {
    let advice: DeviceRecoveryAdvice
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var isShowingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text(advice.title)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss this message")
            }

            // Numbered so the order is obvious; several of these only work in sequence.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(advice.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)

            if !advice.detail.isEmpty {
                DisclosureGroup("Technical details", isExpanded: $isShowingDetail) {
                    Text(advice.detail)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(advice.title)
        .accessibilityValue(advice.steps.joined(separator: ". "))
    }

    private var symbolName: String {
        switch advice.kind {
        case .deviceLocked: return "lock.fill"
        case .noDevice: return "iphone.slash"
        case .sessionConflict: return "exclamationmark.triangle.fill"
        case .timeout: return "clock.badge.exclamationmark"
        case .disconnected: return "cable.connector.slash"
        case .unknown: return "exclamationmark.triangle"
        }
    }
}
