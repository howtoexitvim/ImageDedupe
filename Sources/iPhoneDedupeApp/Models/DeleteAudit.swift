import DeviceMediaKit
import Foundation

struct DeletePlanSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let token: DeviceFileToken
        let filename: String
        let kind: String
        let size: Int64
    }

    let id: UUID
    let date: Date
    let deviceName: String
    let deviceIdentityHash: String?
    let catalogGeneration: UUID?
    let items: [Item]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        deviceName: String,
        deviceIdentityHash: String? = nil,
        items: [Item]
    ) {
        self.id = id
        self.date = date
        self.deviceName = deviceName
        self.deviceIdentityHash = deviceIdentityHash
        self.catalogGeneration = items.first?.token.generation
        self.items = items
    }

    var totalBytes: Int64 {
        items.reduce(0) { $0 + max(0, $1.size) }
    }
}

struct DeleteAudit: Codable, Equatable, Sendable {
    enum VerificationState: String, Codable, Equatable, Sendable {
        case pending
        case verified
    }

    struct Item: Codable, Equatable, Identifiable, Sendable {
        enum Outcome: String, Codable, Equatable, Sendable {
            case confirmedRemoved
            case stillPresent
            case frameworkFailed
            case canceled
            case ambiguous
            case verificationPending

            var title: String {
                switch self {
                case .confirmedRemoved: "Confirmed removed"
                case .stillPresent: "Still present"
                case .frameworkFailed: "Delete failed"
                case .canceled: "Canceled"
                case .ambiguous: "Ambiguous"
                case .verificationPending: "Verification pending"
                }
            }
        }

        var id: DeviceFileToken { token }
        let token: DeviceFileToken
        let filename: String
        let kind: String
        let size: Int64
        let outcome: Outcome
        let reason: String?
    }

    let snapshot: DeletePlanSnapshot
    let verificationState: VerificationState
    let verifiedAt: Date?
    let verificationReason: String?
    let frameworkSummary: DeviceGatewayDeleteSummary?
    let items: [Item]
}

enum DeleteReconciler {
    /// - Parameter keptFingerprints: fingerprints the caller deliberately kept a copy of,
    ///   i.e. the `keep` side of a duplicate group. A surviving file with one of these
    ///   fingerprints is the intended result of deduplication rather than a suspicious
    ///   leftover, so it is reported as removed instead of ambiguous.
    static func reconcile(
        snapshot: DeletePlanSnapshot,
        summary: DeviceGatewayDeleteSummary,
        catalog: DeviceCatalogSnapshot,
        keptFingerprints: Set<DeviceFileFingerprint> = [],
        date: Date = Date()
    ) -> DeleteAudit {
        if let expectedIdentity = snapshot.deviceIdentityHash {
            guard let observedIdentity = catalog.deviceIdentityHash,
                  expectedIdentity == observedIdentity else {
                return unverified(
                    snapshot: snapshot,
                    reason: "The original device identity could not be confirmed; reconnect that device to verify this delete.",
                    frameworkSummary: summary
                )
            }
        }
        let presentByHandle = Dictionary(grouping: catalog.files, by: { $0.token.objectHandle })
        let presentFingerprints = Dictionary(grouping: catalog.files, by: { $0.token.fingerprint })
        let failedReasons = Dictionary(uniqueKeysWithValues: summary.failed.map { ($0.token, $0.reason) })
        let canceled = Set(summary.canceled)
        let successful = Set(summary.successful)

        let items = snapshot.items.map { planned -> DeleteAudit.Item in
            let outcome: DeleteAudit.Item.Outcome
            let reason: String?
            let sameHandle = presentByHandle[planned.token.objectHandle] ?? []
            if sameHandle.contains(where: { $0.token.fingerprint == planned.token.fingerprint }) {
                if let failure = failedReasons[planned.token] {
                    outcome = .frameworkFailed
                    reason = failure
                } else if canceled.contains(planned.token) {
                    outcome = .canceled
                    reason = nil
                } else if successful.contains(planned.token) {
                    outcome = .stillPresent
                    reason = "The framework reported success, but the item remains in the device catalog."
                } else {
                    outcome = .ambiguous
                    reason = "The item remains, but the framework returned no final classification."
                }
            } else if !sameHandle.isEmpty {
                outcome = .ambiguous
                reason = "The device reused this object handle for a different file."
            } else if presentFingerprints[planned.token.fingerprint]?.isEmpty == false {
                if keptFingerprints.contains(planned.token.fingerprint) {
                    // Deduplication: the caller knew an identical copy was being kept, so a
                    // survivor is the intended outcome. Reporting it as ambiguous made a
                    // correct Duplicates delete look like a failure.
                    outcome = .confirmedRemoved
                    reason = "Removed. An identical copy is kept elsewhere on the device."
                } else {
                    // Nothing was supposed to remain, so the device may have renumbered the
                    // file rather than deleting it. Stay cautious.
                    outcome = .ambiguous
                    reason = "A matching file remains under a different device object handle."
                }
            } else {
                outcome = .confirmedRemoved
                reason = nil
            }
            return DeleteAudit.Item(
                token: planned.token,
                filename: planned.filename,
                kind: planned.kind,
                size: planned.size,
                outcome: outcome,
                reason: reason
            )
        }

        return DeleteAudit(
            snapshot: snapshot,
            verificationState: .verified,
            verifiedAt: date,
            verificationReason: nil,
            frameworkSummary: summary,
            items: items
        )
    }

    static func unverified(
        snapshot: DeletePlanSnapshot,
        reason: String,
        frameworkSummary: DeviceGatewayDeleteSummary? = nil
    ) -> DeleteAudit {
        DeleteAudit(
            snapshot: snapshot,
            verificationState: .pending,
            verifiedAt: nil,
            verificationReason: reason,
            frameworkSummary: frameworkSummary,
            items: snapshot.items.map { planned in
                DeleteAudit.Item(
                    token: planned.token,
                    filename: planned.filename,
                    kind: planned.kind,
                    size: planned.size,
                    outcome: .verificationPending,
                    reason: reason
                )
            }
        )
    }
}
