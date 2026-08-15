import Foundation

/// Builds the stable `id` a catalog file is known by across scans.
///
/// This keys the thumbnail and inspector-preview caches, and it is the identity the UI uses
/// for focus and selection, so it must describe the *file* rather than where it happened to
/// appear in an enumeration.
///
/// The id used to be `"\(handle)-\(index)-\(name)"`, where `index` was the file's ordinal
/// in the scan. Deleting one file shifts every later file up a position, which had two
/// consequences after a post-delete scan: a surviving photo lost its cached image because
/// its id changed, and — the visible defect reported on 2026-08-15 — the photo that slid
/// into the vacated position inherited the departed photo's id and was drawn with its
/// cached thumbnail. The tile and the inspector then disagreed.
public enum DeviceMediaFileIdentity {
    /// ImageCaptureCore's "no object handle" value.
    ///
    /// Files reported without a handle all carry `0`, so a handle of `0` distinguishes
    /// nothing — it is the absence of an identifier, not an identifier.
    private static let unassignedObjectHandle: UInt32 = 0

    /// Builds a stable, unique identity for a catalog file.
    ///
    /// Two properties have to hold at once, and getting only one of them caused a bug each:
    ///
    /// - **Stable across scans.** An id containing the file's ordinal meant that deleting
    ///   one file shifted every later file's id, so a surviving photo lost its cached
    ///   thumbnail and the photo sliding into the vacated slot inherited it — the wrong
    ///   picture reported on 2026-08-15.
    /// - **Unique within a catalog.** Dropping the ordinal entirely fixed that and
    ///   introduced a crash: the app builds `Dictionary(uniqueKeysWithValues:)` over these
    ///   ids, which traps on a repeat. A real device produced `0-QVKQ5385.JPG` twice, two
    ///   files sharing both the unassigned handle and a name.
    ///
    /// So position is used **only** when nothing else can separate two files: no real
    /// handle, or no name. A file with a genuine object handle keeps a position-independent
    /// identity, which is what preserves the thumbnail behaviour.
    public static func make(objectHandle: UInt32, name: String?, index: Int) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !(trimmedName ?? "").isEmpty
        let hasHandle = objectHandle != unassignedObjectHandle

        switch (hasHandle, hasName) {
        case (true, true):
            // The normal case: stable across scans and unique, since a real handle is
            // unique within a catalog.
            return "\(objectHandle)-\(trimmedName ?? "")"
        case (true, false):
            return "\(objectHandle)-unnamed"
        case (false, true):
            // No handle to separate same-named files, so position is the only thing left.
            // Such a file cannot keep a stable identity across a delete, and a re-fetched
            // thumbnail is the correct trade against crashing.
            return "nohandle-\(index)-\(trimmedName ?? "")"
        case (false, false):
            return "nohandle-unnamed-\(index)"
        }
    }
}
