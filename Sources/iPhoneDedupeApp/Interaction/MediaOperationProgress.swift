import DeviceMediaKit
import Foundation

struct MediaOperationProgress: Equatable {
    enum Kind: Equatable {
        case importing
        case deleting
    }

    let kind: Kind
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
            return kind == .importing ? "Canceling import…" : "Canceling delete…"
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

    mutating func apply(_ update: DeviceBatchProgress) {
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
