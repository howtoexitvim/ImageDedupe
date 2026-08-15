import Foundation

/// Decides whether an adopted session's `mediaFiles` looks like a finished enumeration.
///
/// `adoptAlreadyBrowsedDevice` publishes an already-open session's `mediaFiles` directly,
/// because `deviceDidBecomeReady(withCompleteContentCatalog:)` fires once per device object
/// and will not fire again. That shortcut is necessary — without it a rescan hangs — but it
/// publishes whatever the framework has enumerated *at that instant*.
///
/// Reported on 2026-08-16: a scan returned 104 files where the device held ~3,952, and the
/// next scan returned the full count. A short catalog is not cosmetic: Duplicates is derived
/// from it, the delete plan from Duplicates, and post-delete verification asks whether a
/// file is "still present" against a catalog that may simply not list it yet.
///
/// This is a plausibility check, not proof. The framework offers no "enumeration finished"
/// signal for an adopted session, so the app waits and re-reads rather than trusting a
/// suspiciously small snapshot.
public enum DeviceCatalogCompleteness {
    /// How far a catalog may shrink before it is treated as still enumerating.
    ///
    /// Generous, because deleting is a normal thing to do here and a real deletion must
    /// never be mistaken for a fault. Losing more than this in one step is far more likely
    /// to be a partially populated cache than a user clearing most of their phone in the
    /// seconds between two scans.
    public static let maximumPlausibleShrinkFraction = 0.5

    /// - Parameters:
    ///   - sourceFileCount: entries the session currently lists.
    ///   - previousFileCount: entries the last accepted catalog for this device held, or
    ///     `nil` when there is no baseline yet.
    ///   - isFromReadinessCallback: true when the framework has explicitly signalled a
    ///     complete catalog, which is authoritative and bypasses the heuristic.
    public static func isPlausiblyComplete(
        sourceFileCount: Int,
        previousFileCount: Int?,
        isFromReadinessCallback: Bool = false
    ) -> Bool {
        // The framework said the catalog is complete; an empty device is a real state.
        if isFromReadinessCallback { return true }

        // Nothing enumerated yet is never a finished catalog on an adopted session.
        guard sourceFileCount > 0 else { return false }

        // A first scan has no baseline, so any content is accepted rather than blocking use.
        guard let previousFileCount, previousFileCount > 0 else { return true }

        let floor = Double(previousFileCount) * (1 - maximumPlausibleShrinkFraction)
        return Double(sourceFileCount) >= floor
    }
}
