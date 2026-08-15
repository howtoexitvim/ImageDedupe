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

    /// Selecting a whole group from its header. With several copies in a group, ticking
    /// each one individually is the tedium the grouped view was meant to avoid.
    func testSelectingAGroupSelectsItsRedundantCopiesOnly() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC"),
            item(id: "a3", name: "A.HEIC"),
            item(id: "b1", name: "B.HEIC"),
            item(id: "b2", name: "B.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        let groupID = viewModel.duplicateGroups[0].id
        viewModel.toggleGroupSelection(groupID: groupID)

        // The kept copy is excluded, exactly as it is from Select All: deleting a whole
        // group must never mean deleting every copy of the file.
        XCTAssertEqual(viewModel.selectedActionIDs, ["a2", "a3"])
    }

    /// The header control toggles: a second press clears the group again.
    func testSelectingAGroupTwiceClearsIt() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        let groupID = viewModel.duplicateGroups[0].id
        viewModel.toggleGroupSelection(groupID: groupID)
        XCTAssertEqual(viewModel.selectedActionIDs, ["a2"])

        viewModel.toggleGroupSelection(groupID: groupID)
        XCTAssertTrue(viewModel.selectedActionIDs.isEmpty)
    }

    /// Selecting one group leaves the others alone.
    func testSelectingAGroupDoesNotDisturbOtherGroups() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC"),
            item(id: "b1", name: "B.HEIC"),
            item(id: "b2", name: "B.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        viewModel.toggleGroupSelection(groupID: viewModel.duplicateGroups[0].id)
        viewModel.toggleGroupSelection(groupID: viewModel.duplicateGroups[1].id)

        XCTAssertEqual(viewModel.selectedActionIDs, ["a2", "b2"])
    }

    /// With three copies, exactly one is kept and the other two are marked — the badges are
    /// not "one tagged file per group". Checked because the tagging looked one-sided.
    func testEveryRedundantCopyIsTaggedNotJustOne() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC"),
            item(id: "a3", name: "A.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        // One blue seal.
        XCTAssertEqual(viewModel.keptDuplicateIDs, ["a1"])
        // Two orange triangles — every copy that Delete would remove.
        XCTAssertEqual(viewModel.duplicateDeleteIDs, ["a2", "a3"])
    }

    /// Searching in Duplicates must filter the files themselves, not just their headers.
    /// The grouped view builds its own order, so the search has to be applied to it rather
    /// than bypassed.
    func testSearchingInDuplicatesFiltersTheFiles() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "APPLE.HEIC"),
            item(id: "a2", name: "APPLE.HEIC"),
            item(id: "b1", name: "BANANA.HEIC"),
            item(id: "b2", name: "BANANA.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)
        XCTAssertEqual(viewModel.visibleItems.count, 4)

        viewModel.applySearchText("BANANA")

        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["b1", "b2"])
    }

    /// A search matching nothing empties the view completely.
    func testASearchMatchingNothingEmptiesDuplicates() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "APPLE.HEIC"),
            item(id: "a2", name: "APPLE.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)

        viewModel.applySearchText("zzzz-no-match")

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    /// The fingerprints handed to verification must describe the copies being *kept*.
    ///
    /// Reported on 2026-08-16: deleting two duplicate groups at once reported both as
    /// "Still present". A kept copy shares its fingerprint with the copy that was deleted,
    /// so verification cannot confirm the delete without being told which fingerprints are
    /// deliberate survivors.
    func testKeptFingerprintsCoverEveryGroupBeingDeletedFrom() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC"),
            item(id: "b1", name: "B.HEIC"),
            item(id: "b2", name: "B.HEIC"),
            item(id: "b3", name: "B.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()

        let kept = viewModel.keptDuplicateFingerprintsForTesting()

        // Both groups must be represented, or the group missing from the set reports its
        // delete as unconfirmed.
        XCTAssertEqual(kept.count, 2, "One fingerprint per duplicate group.")
        XCTAssertTrue(kept.contains(viewModel.allItems[0].token.fingerprint))
        XCTAssertTrue(kept.contains(viewModel.allItems[2].token.fingerprint))
    }

    /// The set must survive the rows being hidden. Verification runs after the delete, by
    /// which point the deleted rows may already be gone from `allItems`.
    func testKeptFingerprintsSurviveTheDeletedRowsBeingRemoved() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()

        // The redundant copy is hidden as soon as the device reports it removed.
        viewModel.applySuccessfulDeletion(itemIDs: ["a2"])

        let kept = viewModel.keptDuplicateFingerprintsForTesting()
        XCTAssertFalse(
            kept.isEmpty,
            "The kept copy's fingerprint must still be known when verification runs."
        )
    }

    /// Switching scope must clear the action selection.
    ///
    /// Reported on 2026-08-16: items ticked in Duplicates were still selected after
    /// switching to All Media. That is worse than untidy — Delete acts on the action
    /// selection, so a user who selected a group in Duplicates, switched away, and pressed
    /// Delete would be acting on files they can no longer see in context.
    func testSwitchingScopeClearsTheActionSelection() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC"),
            item(id: "solo", name: "SOLO.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)
        viewModel.toggleActionSelection(withID: "a2")
        XCTAssertEqual(viewModel.selectedActionIDs, ["a2"])

        viewModel.selectReviewScope(.allMedia)

        XCTAssertTrue(
            viewModel.selectedActionIDs.isEmpty,
            "A selection made in another scope must not silently survive the switch."
        )
    }

    /// Focus is cleared with it, so the inspector does not keep showing a file the new
    /// scope may not list.
    func testSwitchingScopeClearsFocusToo() {
        let viewModel = makeViewModel()
        viewModel.allItems = [
            item(id: "a1", name: "A.HEIC"),
            item(id: "a2", name: "A.HEIC")
        ]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)
        viewModel.selectItem(withID: "a2")
        XCTAssertEqual(viewModel.selectedItemID, "a2")

        viewModel.selectReviewScope(.allMedia)

        XCTAssertNil(viewModel.selectedItemID)
    }

    /// Re-selecting the scope already showing must not clear a selection in progress.
    func testReselectingTheSameScopeKeepsTheSelection() {
        let viewModel = makeViewModel()
        viewModel.allItems = [item(id: "a1", name: "A.HEIC"), item(id: "a2", name: "A.HEIC")]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)
        viewModel.toggleActionSelection(withID: "a2")

        viewModel.selectReviewScope(.duplicates)

        XCTAssertEqual(viewModel.selectedActionIDs, ["a2"])
    }

    /// A pending delete is planned against the files visible when it was confirmed, so
    /// changing scope must retire it rather than let it fire against a different view.
    func testSwitchingScopeDiscardsAPendingDeleteSnapshot() {
        let viewModel = makeViewModel()
        viewModel.allItems = [item(id: "a1", name: "A.HEIC"), item(id: "a2", name: "A.HEIC")]
        viewModel.recomputeDuplicatePlanForTesting()
        viewModel.selectReviewScope(.duplicates)
        viewModel.toggleActionSelection(withID: "a2")
        viewModel.requestDeleteConfirmation()
        XCTAssertNotNil(viewModel.pendingDeleteSnapshot)

        viewModel.selectReviewScope(.allMedia)

        XCTAssertNil(viewModel.pendingDeleteSnapshot)
    }

    /// Downloading a whole duplicate group must not crash.
    ///
    /// Reported on 2026-08-16: batch download crashed in
    /// `Dictionary(uniqueKeysWithValues:)` inside `importSelected`, keyed by token.
    ///
    /// This was a direct consequence of keeping every duplicate file: on a device that
    /// assigns no object handles, two copies of one file share a token, so a duplicate group
    /// legitimately contains repeated tokens. Any dictionary keyed by token now traps, and
    /// the trap kills the app mid-download rather than failing one file.
    func testDownloadingItemsThatShareATokenDoesNotTrap() {
        let viewModel = makeViewModel()
        let shared = DeviceFileToken.fixture(objectHandle: 0, name: "A.HEIC")
        viewModel.allItems = [
            MediaBrowserViewModel.MediaItem(model: file(id: "a1", name: "A.HEIC"), token: shared),
            MediaBrowserViewModel.MediaItem(model: file(id: "a2", name: "A.HEIC"), token: shared)
        ]
        viewModel.recomputeDuplicatePlanForTesting()

        // The mapping the crash site builds. It must tolerate a repeated key.
        let itemByToken = viewModel.itemsByTokenForTesting()

        XCTAssertEqual(itemByToken.count, 1, "One entry per token, not a trap.")
        XCTAssertNotNil(itemByToken[shared])
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
