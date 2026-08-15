import Foundation

/// Turns a device failure into something the user can act on.
///
/// Reported 2026-08-15: an iPhone auto-locked partway through a 4,000-item scan,
/// ImageCaptureCore refused the session, and the only feedback was one line of truncated
/// status text. The user reasonably concluded the app was broken. Every failure now names
/// what happened and what to do about it.
///
/// Classification is by message content because ImageCaptureCore reports most of these as
/// generic errors; matching on text is unattractive but it is the information available.
public struct DeviceRecoveryAdvice: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case deviceLocked
        case noDevice
        case sessionConflict
        case timeout
        case disconnected
        case unknown
    }

    public let kind: Kind

    /// The original failure text, preserved so a problem outside these categories is still
    /// diagnosable.
    public let detail: String

    public init(kind: Kind, detail: String) {
        self.kind = kind
        self.detail = detail
    }

    /// Short enough for the status bar, which truncates.
    public var title: String {
        switch kind {
        case .deviceLocked: return "iPhone is locked"
        case .noDevice: return "No iPhone found"
        case .sessionConflict: return "Another app is using the iPhone"
        case .timeout: return "The iPhone stopped responding"
        case .disconnected: return "iPhone disconnected"
        case .unknown: return "Could not reach the iPhone"
        }
    }

    /// Ordered, concrete actions. Every kind has at least one, so no failure is a dead end.
    public var steps: [String] {
        switch kind {
        case .deviceLocked:
            return [
                "Unlock the iPhone and keep the screen on.",
                "Set Settings → Display & Brightness → Auto-Lock to Never while scanning; a large scan can outlast the timer.",
                "If a Trust This Mac prompt appears, tap Trust.",
                "Then scan again."
            ]
        case .noDevice:
            return [
                "Connect the iPhone with a cable that supports data, not charging only.",
                "Unlock the iPhone and tap Trust if prompted.",
                "Try a different USB port.",
                "Then scan again."
            ]
        case .sessionConflict:
            return [
                "Quit Image Capture, Photos, and any other app reading the iPhone.",
                "Disconnect and reconnect the iPhone.",
                "Then scan again."
            ]
        case .timeout:
            return [
                "Keep the iPhone unlocked and awake.",
                "Avoid unplugging it while a scan, import, or delete is running.",
                "Then try again."
            ]
        case .disconnected:
            return [
                "Reconnect the iPhone and unlock it.",
                "Check the cable if it disconnects repeatedly.",
                "Then scan again to refresh the catalog."
            ]
        case .unknown:
            return [
                "Unlock the iPhone and keep it awake.",
                "Quit Image Capture and Photos, then reconnect the iPhone.",
                "Then try again."
            ]
        }
    }

    /// Classifies a failure message. Ordered most specific first: a message can mention
    /// both a timeout and a lock, and the lock is the actionable cause.
    public static func forFailure(_ message: String) -> DeviceRecoveryAdvice {
        let text = message.lowercased()

        let kind: Kind
        // "unlock" matters as much as "locked": ImageCaptureCore's own wording is
        // "Please unlock “<device>”", which fell through to `.unknown` and so gave the user
        // no guidance at all when they scanned with the phone locked.
        if text.contains("locked") || text.contains("unlock")
            || text.contains("access restricted") || text.contains("access-restricted") {
            kind = .deviceLocked
        } else if text.contains("no imagecapturecore camera") || text.contains("no device") {
            kind = .noDevice
        } else if text.contains("busy") || text.contains("in use") || text.contains("another app") {
            kind = .sessionConflict
        } else if text.contains("disconnect") {
            kind = .disconnected
        } else if text.contains("timed out") || text.contains("timeout") {
            kind = .timeout
        } else {
            kind = .unknown
        }

        return DeviceRecoveryAdvice(kind: kind, detail: message)
    }
}
