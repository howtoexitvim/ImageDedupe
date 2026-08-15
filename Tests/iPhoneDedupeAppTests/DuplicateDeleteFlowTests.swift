import AppKit
import DeduperCore
import DeviceMediaKit
import Foundation
import XCTest
@testable import iPhoneDedupeApp

/// Deleting from the Duplicates view.
///
/// A user reported that deleted files "were still in the list" and only disappeared after
/// deleting a second time. The device was checked and the deletes had in fact succeeded:
/// Duplicates deliberately lists only the redundant copy of each group, so one copy of the
/// file legitimately remains on the phone afterwards. These tests pin that behavior down so
/// it is not mistaken for a delete failure again.
@MainActor
final class DuplicateDeleteFlowTests: XCTestCase {
    func testDuplicatesScopeShowsOnlyTheRedundantCopyNotBothFiles() {
        let keep = file(id: "keep", name: "IMG_1.HEIC")
        let redundant = file(id: "redundant", name: "IMG_1.HEIC")
        let plan = DuplicatePlan(keep: [keep], delete: [redundant])

        let visible = MediaReviewScope.duplicates.apply(
            to: [keep, redundant],
            duplicatePlan: plan
        )

        XCTAssertEqual(visible.map(\.id), ["redundant"])
    }

    func testDeletingTheRedundantCopyLeavesTheKeptCopyOnTheDevice() {
        let viewModel = makeViewModel()
        let keep = item(id: "keep", name: "IMG_1.HEIC")
        let redundant = item(id: "redundant", name: "IMG_1.HEIC")
        viewModel.allItems = [keep, redundant]
        viewModel.duplicatePlan = DuplicatePlan(keep: [keep.model], delete: [redundant.model])
        viewModel.refreshVisibleOrder()

        viewModel.applySuccessfulDeletion(itemIDs: ["redundant"])

        // The kept copy is intentionally still there; that is not a failed delete.
        XCTAssertEqual(viewModel.allItems.map(\.id), ["keep"])
    }

    func testDeletingTheRedundantCopyEmptiesTheDuplicatesView() {
        let viewModel = makeViewModel()
        let keep = item(id: "keep", name: "IMG_1.HEIC")
        let redundant = item(id: "redundant", name: "IMG_1.HEIC")
        viewModel.allItems = [keep, redundant]
        viewModel.duplicatePlan = DuplicatePlan(keep: [keep.model], delete: [redundant.model])
        viewModel.selectReviewScope(.duplicates)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["redundant"])

        viewModel.applySuccessfulDeletion(itemIDs: ["redundant"])

        // The plan is recomputed, so the group is no longer a duplicate and the row goes.
        XCTAssertTrue(
            viewModel.visibleItems.isEmpty,
            "A resolved duplicate group must leave the Duplicates view."
        )
        XCTAssertTrue(viewModel.duplicatePlan.delete.isEmpty)
    }

    func testDeletingOneOfThreeCopiesKeepsTheRemainingGroupVisible() {
        let viewModel = makeViewModel()
        let keep = item(id: "keep", name: "IMG_2.HEIC")
        let second = item(id: "second", name: "IMG_2.HEIC")
        let third = item(id: "third", name: "IMG_2.HEIC")
        viewModel.allItems = [keep, second, third]
        viewModel.duplicatePlan = DuplicatePlan(
            keep: [keep.model],
            delete: [second.model, third.model]
        )
        viewModel.selectReviewScope(.duplicates)

        viewModel.applySuccessfulDeletion(itemIDs: ["second"])

        // Two copies remain, so one is still redundant and stays listed.
        XCTAssertEqual(viewModel.allItems.count, 2)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["third"])
    }

    // MARK: - Results sheet must not interrupt a clean delete

    func testCleanDeleteDoesNotAutoPresentTheResultsSheet() async {
        let viewModel = makeViewModel()
        let item = self.item(id: "gone", name: "IMG_9.HEIC")
        viewModel.allItems = [item]
        viewModel.refreshVisibleOrder()

        // Verification is disabled, so the record is `verificationPending`. That is not an
        // issue worth interrupting the user with — the delete itself succeeded.
        viewModel.startDeleteVerificationForTesting(
            snapshot: DeletePlanSnapshot(
                deviceName: "iPhone",
                items: [
                    DeletePlanSnapshot.Item(
                        token: item.token,
                        filename: item.model.name,
                        kind: "HEIC",
                        size: 1_000
                    )
                ]
            ),
            summary: DeviceGatewayDeleteSummary(successful: [item.token])
        )
        await waitUntilIdle(viewModel)

        XCTAssertFalse(
            viewModel.isShowingOperationHistory,
            "A delete with no real failure must not pop the debug Results sheet."
        )
        XCTAssertFalse(
            viewModel.operationHistory.isEmpty,
            "The record must still be reviewable when Results is opened deliberately."
        )
    }

    func testRealFailureStillDeservesAttention() {
        let token = DeviceFileToken.fixture(objectHandle: 5, name: "IMG_8.HEIC")
        let snapshot = DeletePlanSnapshot(
            deviceName: "iPhone",
            items: [
                DeletePlanSnapshot.Item(
                    token: token,
                    filename: "IMG_8.HEIC",
                    kind: "HEIC",
                    size: 1_000
                )
            ]
        )
        let summary = DeviceGatewayDeleteSummary(failed: [
            DeviceOperationFailure(
                token: token,
                filename: "IMG_8.HEIC",
                reason: "The device refused the delete."
            )
        ])
        // Unverified because verification is off, but the framework did report a failure,
        // which must still interrupt the user.
        let audit = DeleteReconciler.unverified(
            snapshot: snapshot,
            reason: "Submitted to the device; not verified against a fresh catalog.",
            frameworkSummary: summary
        )

        let record = OperationResultRecord(
            id: snapshot.id,
            date: snapshot.date,
            kind: .deleting,
            destinationPath: nil,
            requestedCount: 1,
            successfulCount: 0,
            failures: [OperationResultRecord.Failure(filename: "IMG_8.HEIC", reason: "refused")],
            canceledFilenames: [],
            deleteAudit: audit
        )

        XCTAssertTrue(record.deservesAttention)
    }

    func testPendingVerificationAloneDoesNotDeserveAttention() {
        let token = DeviceFileToken.fixture(objectHandle: 6, name: "IMG_7.HEIC")
        let snapshot = DeletePlanSnapshot(
            deviceName: "iPhone",
            items: [
                DeletePlanSnapshot.Item(
                    token: token,
                    filename: "IMG_7.HEIC",
                    kind: "HEIC",
                    size: 1_000
                )
            ]
        )
        // A clean delete: the framework reported success, only verification is switched off.
        let audit = DeleteReconciler.unverified(
            snapshot: snapshot,
            reason: "Submitted to the device; not verified against a fresh catalog.",
            frameworkSummary: DeviceGatewayDeleteSummary(successful: [token])
        )

        let record = OperationResultRecord(
            id: snapshot.id,
            date: snapshot.date,
            kind: .deleting,
            destinationPath: nil,
            requestedCount: 1,
            successfulCount: 1,
            failures: [OperationResultRecord.Failure(filename: "IMG_7.HEIC", reason: "pending")],
            canceledFilenames: [],
            deleteAudit: audit
        )

        XCTAssertFalse(
            record.deservesAttention,
            "A clean delete must not pop the debug Results sheet."
        )
        XCTAssertTrue(record.shouldPersist, "It must still be reviewable in Results.")
    }

    private func waitUntilIdle(_ viewModel: MediaBrowserViewModel) async {
        for _ in 0..<2_000 where viewModel.isDeviceBusy {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: - Helpers

    private func makeViewModel() -> MediaBrowserViewModel {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duplicate-delete-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directoryURL) }
        return MediaBrowserViewModel(
            operationResultStore: OperationResultStore(
                fileURL: directoryURL.appendingPathComponent("history.json")
            )
        )
    }

    private func file(id: String, name: String) -> DeviceMediaFile {
        DeviceMediaFile(
            id: id,
            name: name,
            kind: "HEIC",
            size: 1_000,
            timestamp: nil,
            width: nil,
            height: nil
        )
    }

    private func item(id: String, name: String) -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: file(id: id, name: name),
            token: .fixture(objectHandle: UInt32(abs(id.hashValue % 10_000)), name: name)
        )
    }
}
