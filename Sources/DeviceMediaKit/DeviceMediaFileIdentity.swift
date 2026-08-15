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
    /// `index` is used only when there is no name to distinguish a file by, which is the
    /// one case where position is better than nothing.
    public static func make(objectHandle: UInt32, name: String?, index: Int) -> String {
        guard let name, !name.isEmpty else {
            return "\(objectHandle)-unnamed-\(index)"
        }
        return "\(objectHandle)-\(name)"
    }
}
