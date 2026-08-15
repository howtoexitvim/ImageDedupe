import DeviceMediaKit
import SwiftUI

/// Asks what to do when a download would land on a filename already at the destination.
///
/// The app deliberately has no silent default here. Replacing destroys a file the user
/// already has; skipping loses one they just asked for. Both are reasonable in different
/// situations and neither is safe to assume, so the choice is theirs.
///
/// "Apply to all" covers the rest of *this* import only. Carrying it into a later session
/// would mean silently replacing files because of a tick box from an earlier one.
struct ImportConflictSheet: View {
    let conflict: MediaBrowserViewModel.ImportConflict
    let onResolve: (ImportConflictResolution, Bool) -> Void
    let onCancel: () -> Void

    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(conflict.filename) already exists")
                .font(.headline)

            Text("A file with this name is already in the destination folder. Duplicates share a name, so this is expected when downloading a duplicate group.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if conflict.remainingCount > 0 {
                Toggle(
                    "Apply to the remaining \(conflict.remainingCount) file(s) in this download",
                    isOn: $applyToAll
                )
                .toggleStyle(.checkbox)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip") { onResolve(.skip, applyToAll) }
                Button("Replace") { onResolve(.replace, applyToAll) }
                // Destructive styling, since this is the one option that discards a file
                // the user already has.
                    .foregroundStyle(.red)
                Button("Keep Both") { onResolve(.keepBoth, applyToAll) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
