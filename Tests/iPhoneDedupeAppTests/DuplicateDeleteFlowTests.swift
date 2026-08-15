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
/// deleting from Duplicates removes the redundant copy and leaves the kept one, so a copy
/// legitimately remains on the phone afterwards. These tests pin that down so it is not
/// mistaken for a delete failure again.
///
/// Duplicates now shows *every* copy of a group rather than only the redundant ones, so the
/// user can see which copy survives and compare it. That makes the keeper reachable, and
/// these tests also pin the guard that stops a bulk selection sweeping it up.
@MainActor
final class DuplicateDeleteFlowTests: XCTestCase {
    /// With no grouping supplied, the scope still falls back to listing only the redundant
    /// copies, which keeps every existing caller working unchanged.
    func testDuplicatesScopeWithoutGroupingListsOnlyTheRedundantCopy() {
        let keep = file(id: "keep", name: "IMG_1.HEIC")
        let redundant = file(id: "redundant", name: "IMG_1.HEIC")
        let plan = DuplicatePlan(keep: [keep], delete: [redundant])

        let visible = MediaReviewScope.duplicates.apply(
            to: [keep, redundant],
            duplicatePlan: plan
        )

        XCTAssertEqual(visible.map(\.id), ["redundant"])
    }

    /// Given the grouping, every copy is shown, ordered so a group's members are adjacent.
    func testDuplicatesScopeWithGroupingShowsEveryCopy() {
        let keep = file(id: "keep", name: "IMG_1.HEIC")
        let redundant = file(id: "redundant", name: "IMG_1.HEIC")
        let groups = DuplicateGrouping.groups(
            files: [keep, redundant],
            definition: DuplicateRuleSelection.default.definition
        )

        let visible = MediaReviewScope.duplicates.apply(
            to: [keep, redundant],
            duplicatePlan: DuplicatePlan(keep: [keep], delete: [redundant]),
            duplicateGroups: groups
        )

        XCTAssertEqual(visible.map(\.id), ["keep", "redundant"])
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

        // Two copies remain, so the group is still a duplicate and stays listed.
        XCTAssertEqual(viewModel.allItems.count, 2)
        // Both remaining copies are shown, not only the redundant one. Duplicates used to
        // hide the copy the plan keeps, which made "which one survives?" unanswerable
        // inside the app and left no way to compare a file against its twin.
        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["keep", "third"])
        // The keeper is still identified, so the view can mark it and leave it unchecked.
        XCTAssertEqual(viewModel.keptDuplicateIDs, ["keep"])
    }

    /// Duplicates now shows the copy that will survive alongside the redundant ones, which
    /// creates a hazard that did not exist while it was hidden: Select All would sweep up
    /// the keepers too, and deleting would remove *both* copies of everything.
    ///
    /// So Select All in Duplicates selects only the redundant copies.
    func testSelectAllInDuplicatesNeverSelectsTheKeptCopy() {
        let viewModel = makeViewModel()
        let keep = item(id: "keep", name: "IMG_2.HEIC")
        let redundant = item(id: "redundant", name: "IMG_2.HEIC")
        viewModel.allItems = [keep, redundant]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        // Both copies are visible, which is the point of showing the group.
        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["keep", "redundant"])

        // Select All only acts while the browser owns focus, as Command-A in the search
        // field belongs to that text.
        viewModel.setFocusOwner(.mediaBrowser)
        viewModel.selectAllVisible()

        XCTAssertEqual(
            viewModel.selectedActionIDs,
            ["redundant"],
            "Selecting all duplicates must not mark the copy being kept for deletion."
        )
    }

    /// The keeper can still be selected deliberately — the user may decide the other copy
    /// is the one worth keeping. Only the bulk action refuses to do it for them.
    func testTheKeptCopyCanStillBeSelectedDeliberately() {
        let viewModel = makeViewModel()
        let keep = item(id: "keep", name: "IMG_2.HEIC")
        let redundant = item(id: "redundant", name: "IMG_2.HEIC")
        viewModel.allItems = [keep, redundant]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        viewModel.toggleActionSelection(withID: "keep")

        XCTAssertEqual(viewModel.selectedActionIDs, ["keep"])
    }

    /// Reported by the user: in Duplicates the copies of a group were not next to each
    /// other. Grouping put them in group order, and then the normal sort ran over the
    /// result and scattered them again — a group is only visible as a group if its members
    /// are adjacent, so in Duplicates the grouping order wins.
    func testDuplicatesKeepsGroupMembersAdjacentRegardlessOfSort() {
        let viewModel = makeViewModel()
        // Interleaved on purpose, and with timestamps that would separate the pairs if the
        // normal sort were applied.
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC", timestamp: "2026-01-01T00:00:00.000Z"),
            item(id: "b1", name: "B.HEIC", timestamp: "2026-01-02T00:00:00.000Z"),
            item(id: "a2", name: "A.HEIC", timestamp: "2026-01-03T00:00:00.000Z"),
            item(id: "b2", name: "B.HEIC", timestamp: "2026-01-04T00:00:00.000Z")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        viewModel.setSortForTesting(field: .timestamp, order: .descending)

        let ids = viewModel.visibleItems.map(\.id)
        let aPositions = ["a1", "a2"].compactMap { ids.firstIndex(of: $0) }.sorted()
        let bPositions = ["b1", "b2"].compactMap { ids.firstIndex(of: $0) }.sorted()

        XCTAssertEqual(aPositions.count, 2)
        XCTAssertEqual(bPositions.count, 2)
        XCTAssertEqual(aPositions[1] - aPositions[0], 1, "A's copies must be adjacent.")
        XCTAssertEqual(bPositions[1] - bPositions[0], 1, "B's copies must be adjacent.")
    }

    /// Sorting still works in All Media, which is where it belongs.
    func testAllMediaStillSorts() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "old", name: "A.HEIC", timestamp: "2026-01-01T00:00:00.000Z"),
            item(id: "new", name: "B.HEIC", timestamp: "2026-01-09T00:00:00.000Z")
        ]
        viewModel.selectReviewScope(.allMedia)

        viewModel.setSortForTesting(field: .timestamp, order: .descending)

        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["new", "old"])
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

    private func item(
        id: String,
        name: String,
        timestamp: String? = nil
    ) -> MediaBrowserViewModel.MediaItem {
        var model = file(id: id, name: name)
        if let timestamp {
            model = DeviceMediaFile(
                id: model.id,
                name: model.name,
                kind: model.kind,
                size: model.size,
                timestamp: timestamp,
                width: model.width,
                height: model.height
            )
        }
        return MediaBrowserViewModel.MediaItem(
            model: model,
            token: .fixture(objectHandle: UInt32(abs(id.hashValue % 10_000)), name: name)
        )
    }
}
