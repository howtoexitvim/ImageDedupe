import Foundation

/// Admission control for per-item device requests (thumbnails and metadata).
///
/// Scrolling a large catalog previously enqueued an unbounded, uncancellable pile of
/// requests: every row that appeared started work, nothing was ever withdrawn, and items
/// the user had long scrolled past still held the device's attention ahead of the rows
/// actually on screen.
///
/// This bounds how many requests are in flight and lets the renderer withdraw the ones that
/// no longer matter. It tracks intent only — the actual work is a detached task, which
/// checks `isActive` before publishing its result.
@MainActor
final class MediaRequestQueue {
    private let maxConcurrent: Int
    private var active = Set<String>()

    /// - Parameter maxConcurrent: how many requests may be in flight at once. Clamped to at
    ///   least one, since a zero limit would refuse everything forever.
    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    var activeCount: Int { active.count }

    /// Always zero: this queue refuses rather than buffers. Deferred work would go stale
    /// while the user keeps scrolling, so the renderer re-requests what is still visible
    /// instead.
    var pendingCount: Int { 0 }

    func isActive(_ id: String) -> Bool {
        active.contains(id)
    }

    /// Admits a request if there is a free slot and the same item is not already in flight.
    @discardableResult
    func beginIfAllowed(_ id: String) -> Bool {
        guard !active.contains(id), active.count < maxConcurrent else { return false }
        active.insert(id)
        return true
    }

    func finish(_ id: String) {
        active.remove(id)
    }

    /// Withdraws a request. Its result, if it still arrives, is ignored because `isActive`
    /// no longer reports it.
    func cancel(_ id: String) {
        active.remove(id)
    }

    /// Withdraws every request for an item outside `ids`, freeing slots for the rows the
    /// user is actually looking at.
    func cancelRequests(notIn ids: Set<String>) {
        active.subtract(active.subtracting(ids))
    }

    func cancelAll() {
        active.removeAll()
    }
}
