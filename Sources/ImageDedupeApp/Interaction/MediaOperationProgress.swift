import DeviceMediaKit
import Foundation

struct MediaOperationProgress: Equatable {
    enum Kind: Equatable {
        case importing
        case deleting
    }

    /// Submission and post-delete verification are separate phases.
    ///
    /// Previously the verification rescan ran while the label still said
    /// `Deleting — 1 of 1`, so a device-service wait of up to 180 seconds was presented as
    /// an unbounded destructive operation the user could not meaningfully cancel.
    enum Phase: Equatable {
        case submitting
        case verifying
    }

    let kind: Kind
    private(set) var phase: Phase = .submitting
    private(set) var completedItems: Int
    private(set) var totalItems: Int
    private(set) var currentFilename: String?
    private(set) var fractionCompleted: Double
    private(set) var isCanceling = false

    init(kind: Kind, totalItems: Int) {
        self.kind = kind
        completedItems = 0
        self.totalItems = max(0, totalItems)
        currentFilename = nil
        fractionCompleted = 0
    }

    var canCancel: Bool { !isCanceling }

    var detail: String {
        if isCanceling {
            switch phase {
            case .verifying:
                return "Canceling verification…"
            case .submitting:
                return kind == .importing ? "Canceling import…" : "Canceling delete…"
            }
        }
        if phase == .verifying {
            return "Verifying deletion…"
        }

        let count = "\(completedItems) of \(totalItems)"
        switch kind {
        case .importing:
            if let currentFilename, !currentFilename.isEmpty {
                return "Importing \(currentFilename) — \(count)"
            }
            return "Importing — \(count)"
        case .deleting:
            return "Deleting — \(count)"
        }
    }

    /// Moves to the verification phase. Progress becomes indeterminate, because a catalog
    /// rescan has no per-item count of its own.
    mutating func beginVerification() {
        phase = .verifying
        currentFilename = nil
        fractionCompleted = 0
    }

    mutating func apply(_ update: DeviceBatchProgress) {
        // Submission updates arriving late must not pull the label back out of verification.
        guard phase == .submitting else { return }
        totalItems = max(0, update.totalItems)
        completedItems = min(max(0, update.completedItems), totalItems)
        currentFilename = update.currentFilename
        fractionCompleted = min(max(0, update.fractionCompleted), 1)
    }

    @discardableResult
    mutating func requestCancellation() -> Bool {
        guard !isCanceling else { return false }
        isCanceling = true
        return true
    }
}
