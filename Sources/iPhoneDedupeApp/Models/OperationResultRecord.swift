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
    var shouldPersist: Bool { hasIssues || deleteAudit != nil }
    var isPendingDeleteAudit: Bool { deleteAudit?.verificationState == .pending }

    var summary: String {
        "\(successfulCount) succeeded · \(failures.count) failed · \(canceledFilenames.count) canceled"
    }
}
