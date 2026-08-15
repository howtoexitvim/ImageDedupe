import Foundation

/// Whether a failed `requestOpenSession` is worth retrying.
///
/// A locked iPhone answers with -9943 "Please unlock ...", and retrying is right: the user
/// often unlocks a moment later and the scan then succeeds without their doing anything
/// else. But the retry must be bounded. Unbounded, a scan against a phone the user does not
/// unlock sits until its full 180-second timeout showing nothing, which was reported on
/// 2026-08-15 as the app freezing.
public enum OpenSessionRetry {
    /// Attempts before giving up and reporting that the device needs unlocking.
    ///
    /// At the gateway's one-second retry delay this is a few seconds of grace — long enough
    /// to unlock a phone already in hand, short enough that nobody waits minutes to be told
    /// what to do.
    public static let maximumAttempts = 8

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
