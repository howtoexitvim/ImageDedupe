import Foundation

/// Whether a failed `requestOpenSession` is worth retrying.
///
/// A locked iPhone answers with -9943 "Please unlock ...", and retrying is right: the user
/// often unlocks a moment later and the scan then succeeds without their doing anything
/// else. But the retry must be bounded. Unbounded, a scan against a phone the user does not
/// unlock sits until its full 180-second timeout showing nothing, which was reported on
/// 2026-08-15 as the app freezing.
public enum OpenSessionRetry {
    /// Attempts before giving up and handing control back to the user.
    ///
    /// Deliberately small. At the gateway's one-second retry delay this is about three
    /// seconds — enough to cover a phone that is being unlocked right now, and short enough
    /// that an unattended one reports "iPhone is locked" almost immediately instead of
    /// leaving the user wondering whether the app has hung. Pressing Scan again is one
    /// click, and a visible failure the user can act on beats a longer silent wait.
    public static let maximumAttempts = 3

    public static func shouldRetry(
        domain: String,
        code: Int,
        description: String,
        attempt: Int = 0
    ) -> Bool {
        guard attempt < maximumAttempts else { return false }
        return domain == "com.apple.ImageCaptureCore"
            && code == -9943
            && (description as NSString).range(of: "unlock", options: .caseInsensitive).location != NSNotFound
    }
}
