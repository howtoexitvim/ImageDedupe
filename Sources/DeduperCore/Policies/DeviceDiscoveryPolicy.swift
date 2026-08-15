import Foundation

/// How long a scan waits for ImageCaptureCore to advertise *any* usable device.
///
/// A locked iPhone is not slow — it is not advertised at all. `ICDeviceBrowser` reports
/// nothing, so no session is requested and the "please unlock" retry never runs. Before this
/// existed, that meant the scan sat for its entire 180-second timeout showing no outcome,
/// which is what the user reported as the app hanging on Scan.
///
/// The two waits are deliberately separate. Reading a large catalog can legitimately take a
/// while *once a device is found*, and that keeps the generous scan timeout. Not finding a
/// device at all is a different failure with a different answer — tell the user, and let
/// them retry — so it fails fast instead of inheriting the long one.
public enum DeviceDiscoveryPolicy {
    /// Measured on a real device: a first scan sees the device in about a second, but a
    /// *rescan* takes longer — the previous helper must exit and release the device before a
    /// new process is offered it. Five seconds was tried first and broke every rescan, so
    /// this is deliberately generous: it exists to stop a wait becoming a hang, not to be
    /// tight.
    public static let deadline: Duration = .seconds(25)

    /// The longest a scan may run before the catalog arrives.
    ///
    /// This is a hard ceiling, not a refinement of the deadline above. The deadline depends
    /// on the gateway's own bookkeeping being right, and that assumption has now failed
    /// twice: first the retry counter never advanced because the framework stopped calling
    /// back, then the deadline guard consulted `hasOpenSession`, which a locked iPhone
    /// reports as `true` while serving nothing. Each time the user waited minutes.
    ///
    /// So the wait is also bounded from outside, where no framework callback can influence
    /// it.
    ///
    /// - Parameter previousFileCount: entries the last accepted catalog held, when one is
    ///   known. The ceiling scales with it so a much larger library gets proportionally more
    ///   time: a cap that suits 4,000 files must not fail a user with 60,000.
    ///
    /// Measured on a real device: ~3,960 files enumerate in about 1.1 s once a session is
    /// live, and a rescan adds ~9.8 s for the helper handover. The floor below is therefore
    /// several times the observed cost, and the per-file allowance is roughly two orders of
    /// magnitude above the measured rate — generous on purpose, since this exists only to
    /// stop a wait becoming an apparent hang, never to cut a working scan short.
    public static func scanCeiling(previousFileCount: Int? = nil) -> Duration {
        // Covers the helper handover plus a first scan of a typical library.
        let floor: Duration = .seconds(40)
        guard let previousFileCount, previousFileCount > 0 else { return floor }

        // 10 ms per file: about 40 s for 4,000 files and 10 minutes for 60,000, against a
        // measured rate near 0.3 ms per file.
        let scaled = Duration.milliseconds(previousFileCount * 10)
        return scaled > floor ? scaled : floor
    }

    /// The ceiling with no catalog history, for a first scan.
    public static let scanCeiling: Duration = scanCeiling(previousFileCount: nil)
}
