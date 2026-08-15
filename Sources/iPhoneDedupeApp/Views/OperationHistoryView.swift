import SwiftUI

struct OperationHistoryView: View {
    let records: [OperationResultRecord]
    let warning: String?
    let onRetryVerification: (UUID) -> Void
    let onClear: () -> Void
    let onDone: () -> Void

    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Operation Results")
                    .font(.title2.weight(.semibold))
                Spacer()
                if !records.isEmpty || warning != nil {
                    Button("Clear…", role: .destructive) {
                        isConfirmingClear = true
                    }
                }
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            List {
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("History warning: \(warning)")
                }

                if records.isEmpty, warning == nil {
                    ContentUnavailableView(
                        "No Saved Issues",
                        systemImage: "checkmark.circle",
                        description: Text("Failed or canceled import and delete items appear here.")
                    )
                }

                ForEach(records) { record in
                    Section {
                        LabeledContent("Summary", value: record.summary)
                        if let destinationPath = record.destinationPath {
                            LabeledContent("Destination", value: destinationPath)
                        }

                        if let audit = record.deleteAudit {
                            LabeledContent(
                                "Verification",
                                value: audit.verificationState == .verified ? "Verified" : "Pending"
                            )
                            LabeledContent(
                                "Planned size",
                                value: ByteCountFormatter.string(
                                    fromByteCount: audit.snapshot.totalBytes,
                                    countStyle: .file
                                )
                            )
                            ForEach(audit.items) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(item.filename, systemImage: icon(for: item.outcome))
                                    Text(item.outcome.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let reason = item.reason {
                                        Text(reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                            if audit.verificationState == .pending {
                                Button("Retry Verification") {
                                    onRetryVerification(record.id)
                                }
                            }
                        } else {
                            ForEach(record.failures) { failure in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(failure.filename, systemImage: "xmark.circle")
                                Text(failure.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            }

                            ForEach(Array(record.canceledFilenames.enumerated()), id: \.offset) { _, filename in
                                Label("\(filename) — Canceled", systemImage: "stop.circle")
                            }
                        }
                    } header: {
                        HStack {
                            Text(record.kind.title)
                            Spacer()
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .confirmationDialog(
            "Clear resolved operation results?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Resolved Results", role: .destructive, action: onClear)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes resolved failure and cancellation history from this Mac. Pending delete verification audits are retained for safety.")
        }
    }

    private func icon(for outcome: DeleteAudit.Item.Outcome) -> String {
        switch outcome {
        case .confirmedRemoved: "checkmark.circle"
        case .stillPresent, .frameworkFailed: "xmark.circle"
        case .canceled: "stop.circle"
        case .ambiguous, .verificationPending: "questionmark.circle"
        }
    }
}
