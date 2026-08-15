import DeduperCore
import DeviceMediaKit
import Foundation
import XCTest
@testable import iPhoneDedupeApp

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

    func testChangedHandleWithSameFingerprintIsAmbiguous() {
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

        XCTAssertEqual(audit.items.first?.outcome, .ambiguous)
    }

    func testReusedHandleWithDifferentFingerprintIsAmbiguous() {
        let item = plannedItem(handle: 1, name: "A.HEIC")
        let replacement = plannedItem(handle: 1, name: "DIFFERENT.HEIC")

        let audit = DeleteReconciler.reconcile(
            snapshot: DeletePlanSnapshot(deviceName: "iPhone", items: [item]),
            summary: DeviceGatewayDeleteSummary(successful: [item.token]),
            catalog: catalog(containing: replacement, generation: UUID())
        )

        XCTAssertEqual(audit.items.first?.outcome, .ambiguous)
        XCTAssertTrue(audit.items.first?.reason?.contains("reused") == true)
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
}
