import SwiftUI

struct OperationHistoryView: View {
    let records: [OperationResultRecord]
    let warning: String?
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
            "Clear all saved operation results?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Results", role: .destructive, action: onClear)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved failure and cancellation history from this Mac.")
        }
    }
}
