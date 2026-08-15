import DeduperCore
import DeviceMediaKit
import Foundation
import XCTest
@testable import ImageDedupeApp

final class DeleteReconcilerTests: XCTestCase {
    func testAbsentItemIsConfirmedRemovedEvenWhenFrameworkCallbackFailed() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let snapshot = DeletePlanSnapshot(deviceName: "iPhone", items: [item])
        let summary = DeviceGatewayDeleteSummary(
            failed: [DeviceOperationFailure(token: item.token, filename: item.filename, reason: "callback error")]
        )

        let audit = DeleteReconciler.reconcile(snapshot: snapshot, summary: summary, catalog: emptyCatalog())

        XCTAssertEqual(audit.verificationState, .verified)
        XCTAssertEqual(audit.items.first?.outcome, .confirmedRemoved)
    }

    func testStillPresentItemOverridesSuccessfulCallback() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let snapshot = DeletePlanSnapshot(deviceName: "iPhone", items: [item])
        let summary = DeviceGatewayDeleteSummary(successful: [item.token])

        let audit = DeleteReconciler.reconcile(
            snapshot: snapshot,
            summary: summary,
            catalog: catalog(containing: item, generation: UUID())
        )

        XCTAssertEqual(audit.items.first?.outcome, .stillPresent)
    }

    func testPresentFailedAndCanceledItemsKeepTheirFrameworkOutcome() {
        let failed = plannedItem(handle: 1, name: "A.HEIC")
        let canceled = plannedItem(handle: 2, name: "B.MOV")
        let snapshot = DeletePlanSnapshot(deviceName: "iPhone", items: [failed, canceled])
        let summary = DeviceGatewayDeleteSummary(
            failed: [DeviceOperationFailure(token: failed.token, filename: failed.filename, reason: "locked")],
            canceled: [canceled.token]
        )

        let audit = DeleteReconciler.reconcile(
            snapshot: snapshot,
            summary: summary,
            catalog: catalog(containing: failed, canceled, generation: UUID())
        )

        XCTAssertEqual(audit.items.map(\.outcome), [.frameworkFailed, .canceled])
        XCTAssertEqual(audit.items.first?.reason, "locked")
    }

    /// A file whose fingerprint is still in the catalog has not been removed, whatever
    /// object handle it now sits under. The handle may change for reasons that have nothing
    /// to do with this delete, so the fingerprint is what decides presence.
    func testSameFingerprintUnderADifferentHandleIsStillPresent() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let changed = DeletePlanSnapshot.Item(
            token: DeviceFileToken(
                generation: UUID(),
                objectHandle: 99,
                fingerprint: item.token.fingerprint
            ),
            filename: item.filename,
            kind: item.kind,
            size: item.size
        )

        let audit = DeleteReconciler.reconcile(
            snapshot: DeletePlanSnapshot(deviceName: "iPhone", items: [item]),
            summary: DeviceGatewayDeleteSummary(successful: [item.token]),
            catalog: catalog(containing: changed, generation: changed.token.generation)
        )

        XCTAssertEqual(audit.items.first?.outcome, .stillPresent)
    }

    /// The false failure reported on 2026-08-15.
    ///
    /// A PTP object handle is a slot, not an identity: once a file is deleted the device is
    /// free to give its handle to something else, and routinely does. Treating an occupied
    /// handle as evidence made three confirmed-successful deletes (`IMG_5090`, `IMG_5091`,
    /// `WUAS3477` — each `exactMatches=0` on a fresh-process scan) report as "Ambiguous:
    /// the device reused this object handle" or "Still present". Only the fingerprint's
    /// absence decides removal.
    func testReusedHandleForADifferentFileIsStillARemoval() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let unrelatedFileNowHoldingThatHandle = plannedItem(handle: 1, name: "DIFFERENT.HEIC")

        let audit = DeleteReconciler.reconcile(
            snapshot: DeletePlanSnapshot(deviceName: "iPhone", items: [item]),
            summary: DeviceGatewayDeleteSummary(successful: [item.token]),
            catalog: catalog(containing: unrelatedFileNowHoldingThatHandle, generation: UUID())
        )

        XCTAssertEqual(audit.items.first?.outcome, .confirmedRemoved)
    }

    func testDifferentDeviceKeepsAuditPendingInsteadOfClaimingRemoval() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let snapshot = DeletePlanSnapshot(
            deviceName: "iPhone",
            deviceIdentityHash: "original-device",
            items: [item]
        )
        let otherDeviceCatalog = DeviceCatalogSnapshot(
            generation: UUID(),
            deviceName: "Another iPhone",
            deviceIdentityHash: "other-device",
            files: []
        )

        let audit = DeleteReconciler.reconcile(
            snapshot: snapshot,
            summary: DeviceGatewayDeleteSummary(successful: [item.token]),
            catalog: otherDeviceCatalog
        )

        XCTAssertEqual(audit.verificationState, .pending)
        XCTAssertEqual(audit.items.first?.outcome, .verificationPending)
    }

    func testMissingObservedDeviceIdentityFailsClosedForIdentifiedSnapshot() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let snapshot = DeletePlanSnapshot(
            deviceName: "iPhone",
            deviceIdentityHash: "original-device",
            items: [item]
        )

        let audit = DeleteReconciler.reconcile(
            snapshot: snapshot,
            summary: DeviceGatewayDeleteSummary(successful: [item.token]),
            catalog: emptyCatalog()
        )

        XCTAssertEqual(audit.verificationState, .pending)
        XCTAssertEqual(audit.items.first?.outcome, .verificationPending)
    }

    func testUnverifiedAuditKeepsEveryItemPending() {
        let items = [plannedItem(handle: 1, name: "A.HEIC"), plannedItem(handle: 2, name: "B.MOV")]
        let snapshot = DeletePlanSnapshot(deviceName: "iPhone", items: items)

        let audit = DeleteReconciler.unverified(snapshot: snapshot, reason: "scan timed out")

        XCTAssertEqual(audit.verificationState, .pending)
        XCTAssertEqual(audit.items.map(\.outcome), [.verificationPending, .verificationPending])
    }

    private func plannedItem(handle: UInt32, name: String) -> DeletePlanSnapshot.Item {
        let kind = String(name.split(separator: ".").last ?? "UNKNOWN")
        return DeletePlanSnapshot.Item(
            token: .fixture(objectHandle: handle, name: name, kind: kind),
            filename: name,
            kind: kind,
            size: 100
        )
    }

    private func emptyCatalog() -> DeviceCatalogSnapshot {
        DeviceCatalogSnapshot(generation: UUID(), deviceName: "iPhone", files: [])
    }

    private func catalog(
        containing items: DeletePlanSnapshot.Item...,
        generation: UUID
    ) -> DeviceCatalogSnapshot {
        DeviceCatalogSnapshot(
            generation: generation,
            deviceName: "iPhone",
            files: items.map { item in
                let token = DeviceFileToken(
                    generation: generation,
                    objectHandle: item.token.objectHandle,
                    fingerprint: item.token.fingerprint
                )
                return DeviceCatalogFile(
                    model: DeviceMediaFile(
                        id: "\(token.objectHandle)-\(item.filename)",
                        name: item.filename,
                        kind: item.kind,
                        size: item.size,
                        timestamp: nil,
                        width: nil,
                        height: nil
                    ),
                    token: token
                )
            }
        )
    }

    /// Deleting the redundant copy of a duplicate group.
    ///
    /// Reported on 2026-08-16: deleting two groups at once reported both as "Still present"
    /// even though the framework said success. The kept copy of a duplicate has the *same
    /// fingerprint* as the copy that was deleted, so a fingerprint-only presence check can
    /// never confirm this delete — it always finds a survivor. `keptFingerprints` is what
    /// distinguishes "a copy survives because we meant it to" from "nothing was removed".
    func testDeletingADuplicateWhoseTwinIsKeptIsConfirmed() {
        let deleted = plannedItem(handle: 0, name: "WDAW8576.JPG")
        // The kept twin: identical fingerprint, still in the catalog afterwards.
        let survivor = plannedItem(handle: 0, name: "WDAW8576.JPG")

        let audit = DeleteReconciler.reconcile(
            snapshot: DeletePlanSnapshot(deviceName: "iPhone", items: [deleted]),
            summary: DeviceGatewayDeleteSummary(successful: [deleted.token]),
            catalog: catalog(containing: survivor, generation: survivor.token.generation),
            keptFingerprints: [deleted.token.fingerprint]
        )

        XCTAssertEqual(
            audit.items.first?.outcome,
            .confirmedRemoved,
            "A surviving copy the plan deliberately keeps is deduplication working."
        )
    }

    /// Without that signal the same catalog must stay cautious, since an identical file
    /// remaining could equally mean nothing was deleted.
    func testTheSameCatalogWithoutAKeptFingerprintStaysCautious() {
        let deleted = plannedItem(handle: 0, name: "WDAW8576.JPG")
        let survivor = plannedItem(handle: 0, name: "WDAW8576.JPG")

        let audit = DeleteReconciler.reconcile(
            snapshot: DeletePlanSnapshot(deviceName: "iPhone", items: [deleted]),
            summary: DeviceGatewayDeleteSummary(successful: [deleted.token]),
            catalog: catalog(containing: survivor, generation: survivor.token.generation)
        )

        XCTAssertEqual(audit.items.first?.outcome, .stillPresent)
    }
}
