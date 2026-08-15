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

    var hasIssues: Bool { !failures.isEmpty || !canceledFilenames.isEmpty }

    var summary: String {
        "\(successfulCount) succeeded · \(failures.count) failed · \(canceledFilenames.count) canceled"
    }
}
