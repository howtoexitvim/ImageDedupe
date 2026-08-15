import Foundation

struct OperationResultRecord: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case importing
        case deleting

        var title: String {
            switch self {
            case .importing: "Import"
            case .deleting: "Delete"
            }
        }
    }

    struct Failure: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let filename: String
        let reason: String

        init(id: UUID = UUID(), filename: String, reason: String) {
            self.id = id
            self.filename = filename
            self.reason = reason
        }
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let destinationPath: String?
    let requestedCount: Int
    let successfulCount: Int
    let failures: [Failure]
    let canceledFilenames: [String]
    let deleteAudit: DeleteAudit?

    init(
        id: UUID,
        date: Date,
        kind: Kind,
        destinationPath: String?,
        requestedCount: Int,
        successfulCount: Int,
        failures: [Failure],
        canceledFilenames: [String],
        deleteAudit: DeleteAudit? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.destinationPath = destinationPath
        self.requestedCount = requestedCount
        self.successfulCount = successfulCount
        self.failures = failures
        self.canceledFilenames = canceledFilenames
        self.deleteAudit = deleteAudit
    }

    var hasIssues: Bool { !failures.isEmpty || !canceledFilenames.isEmpty }

    /// Whether this result is worth interrupting the user with.
    ///
    /// Distinct from `hasIssues`. With automatic post-delete verification disabled, every
    /// delete records `verificationPending`, which counts as a failure — so a perfectly
    /// clean delete was popping the Results sheet every time and reporting files that were
    /// in fact removed as "Verification pending". Only a real framework failure or
    /// cancellation deserves the interruption; pending-verification records stay reviewable
    /// in Results without presenting themselves.
    var deservesAttention: Bool {
        if !canceledFilenames.isEmpty { return true }
        guard let audit = deleteAudit else { return !failures.isEmpty }
        // A framework failure is still a failure even when the audit could not be verified,
        // so consult the submission result rather than the verification outcome alone.
        if let summary = audit.frameworkSummary, !summary.failed.isEmpty {
            return true
        }
        return audit.items.contains { item in
            switch item.outcome {
            case .frameworkFailed, .stillPresent, .ambiguous:
                return true
            case .confirmedRemoved, .canceled, .verificationPending:
                return false
            }
        }
    }
    var shouldPersist: Bool { hasIssues || deleteAudit != nil }
    var isPendingDeleteAudit: Bool { deleteAudit?.verificationState == .pending }

    var summary: String {
        "\(successfulCount) succeeded · \(failures.count) failed · \(canceledFilenames.count) canceled"
    }
}
