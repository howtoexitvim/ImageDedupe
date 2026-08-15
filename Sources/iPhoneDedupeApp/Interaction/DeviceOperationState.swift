import Foundation

/// One state machine for every device operation, plus the session generation that makes
/// stale asynchronous results identifiable.
///
/// Before this, scan guarded itself with an `isScanning` flag while import and delete had
/// no guard at all, so a delete could start while an import was still writing files. And
/// nothing marked which scan a thumbnail or metadata result belonged to, so a slow request
/// from a previous scan could complete after a new one and mutate the current caches.
///
/// A pure value type so the admission rules can be tested without a device.
struct DeviceOperationState: Equatable {
    enum Operation: String, CaseIterable, Equatable {
        case idle
        case scanning
        case importing
        case deleting

        /// Present-participle form for status text.
        var verb: String {
            switch self {
            case .idle: return "Idle"
            case .scanning: return "Scanning"
            case .importing: return "Importing"
            case .deleting: return "Deleting"
            }
        }
    }

    private(set) var current: Operation = .idle

    /// Identifies the current device session. Incremented by each scan, because a scan is
    /// what replaces the catalog and therefore invalidates in-flight per-item work.
    private(set) var generation: Int = 0

    var isBusy: Bool { current != .idle }

    init() {}

    /// Whether `operation` may start now. Any operation in progress blocks every other,
    /// including a second copy of itself.
    func canBegin(_ operation: Operation) -> Bool {
        guard operation != .idle else { return false }
        return current == .idle
    }

    /// Attempts to start `operation`. Returns whether it was admitted; callers must not
    /// touch the device when this returns `false`.
    @discardableResult
    mutating func begin(_ operation: Operation) -> Bool {
        guard canBegin(operation) else { return false }
        current = operation
        if operation == .scanning {
            // Only a scan invalidates the catalog, so only a scan opens a new session.
            // Import and delete operate within the current one.
            generation &+= 1
        }
        return true
    }

    mutating func finish() {
        current = .idle
    }

    /// Distinct from `finish()` at the call site so failure handling reads clearly; both
    /// return to idle so the user can retry.
    mutating func fail() {
        current = .idle
    }

    /// Whether a result tagged with `generation` still belongs to the active session.
    func isCurrent(generation: Int) -> Bool {
        generation == self.generation
    }
}
