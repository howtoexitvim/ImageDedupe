import Foundation

/// Builds the spoken description of a media item.
///
/// Shared by the List row and the Grid tile so VoiceOver announces the same information in
/// either view. Lives in the domain layer because it is pure text derived from the model,
/// and because it must be testable without a window.
public enum MediaAccessibilityLabel {
    /// A single sentence naming the item and its most useful attributes.
    ///
    /// Order matters for VoiceOver: the filename comes first because that is how users
    /// identify an item, and status flags come last because they are the least common.
    public static func describe(
        _ file: DeviceMediaFile,
        format: MediaDisplayFormat = MediaDisplayFormat(),
        isSelected: Bool = false,
        isImported: Bool = false,
        isDuplicateCandidate: Bool = false
    ) -> String {
        var parts: [String] = [file.name, file.kind.uppercased(), format.fileSize(file.size)]

        if let duration = format.duration(file.duration) {
            parts.append("duration \(duration)")
        }
        if let timestamp = format.timestamp(file.timestamp) {
            parts.append(timestamp)
        }

        if isDuplicateCandidate {
            parts.append("duplicate candidate")
        }
        if isImported {
            parts.append("imported")
        }
        // Selection is announced last so it does not bury the item's identity, and is
        // stated explicitly in both directions because "not selected" is meaningful when
        // the user is reviewing what a delete will act on.
        parts.append(isSelected ? "selected" : "not selected")

        return parts.joined(separator: ", ")
    }
}
