import XCTest

@testable import DeduperCore

/// Duplicates used to list only the redundant copies, hiding the copy the app intends to
/// keep. That made the dangerous question — "which one survives?" — unanswerable inside the
/// app, and it meant a file's metadata could not be compared against its twin.
///
/// Grouping shows every copy, ordered so a group's members are adjacent, with the kept copy
/// marked. The delete selection still defaults to exactly the redundant copies, so a user
/// with a hundred groups does not have to click through them one at a time.
final class DuplicateGroupingTests: XCTestCase {
    private func file(id: String, name: String, size: Int64 = 1_000) -> DeviceMediaFile {
        DeviceMediaFile(
            id: id,
            name: name,
            kind: "HEIC",
            size: size,
            timestamp: "2026-08-15T00:00:00.000Z",
            width: nil,
            height: nil
        )
    }

    func testGroupsContainEveryCopyNotJustTheRedundantOnes() {
        let files = [
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC")
        ]
        let groups = DuplicateGrouping.groups(
            files: files,
            definition: DuplicateRuleSelection.default.definition
        )

        XCTAssertEqual(groups.count, 1, "B has no twin, so it is not a duplicate group.")
        XCTAssertEqual(groups[0].members.map(\.file.id), ["a1", "a2"])
    }

    /// Exactly one member per group is the keeper, and it is the first occurrence — the same
    /// choice `DuplicatePlanner` makes, so the group view and the delete plan cannot
    /// disagree about which copy survives.
    func testTheFirstCopyIsTheKeeperAndTheRestAreRedundant() {
        let groups = DuplicateGrouping.groups(
            files: [
                file(id: "a1", name: "A.HEIC"),
                file(id: "a2", name: "A.HEIC"),
                file(id: "a3", name: "A.HEIC")
            ],
            definition: DuplicateRuleSelection.default.definition
        )

        let group = groups[0]
        XCTAssertEqual(group.members.filter(\.isKept).map(\.file.id), ["a1"])
        XCTAssertEqual(group.members.filter { !$0.isKept }.map(\.file.id), ["a2", "a3"])
    }

    /// What the Delete button acts on by default: every redundant copy, and never a keeper.
    /// This is what spares the user a hundred individual clicks.
    func testTheDefaultSelectionIsEveryRedundantCopyAndNoKeeper() {
        let groups = DuplicateGrouping.groups(
            files: [
                file(id: "a1", name: "A.HEIC"),
                file(id: "a2", name: "A.HEIC"),
                file(id: "b1", name: "B.HEIC", size: 2_000),
                file(id: "b2", name: "B.HEIC", size: 2_000)
            ],
            definition: DuplicateRuleSelection.default.definition
        )

        XCTAssertEqual(DuplicateGrouping.defaultSelection(in: groups), ["a2", "b2"])
    }

    /// Members of a group must be adjacent in the flattened order, or the grid would
    /// interleave groups and the pairing would be invisible.
    func testFlattenedOrderKeepsEachGroupsMembersAdjacent() {
        let groups = DuplicateGrouping.groups(
            files: [
                file(id: "a1", name: "A.HEIC"),
                file(id: "b1", name: "B.HEIC", size: 2_000),
                file(id: "a2", name: "A.HEIC"),
                file(id: "b2", name: "B.HEIC", size: 2_000)
            ],
            definition: DuplicateRuleSelection.default.definition
        )

        let ids = groups.flatMap { $0.members.map(\.file.id) }
        XCTAssertEqual(ids, ["a1", "a2", "b1", "b2"])
    }

    /// A file with no twin never appears, so Duplicates stays a review list rather than
    /// becoming a second All Media.
    func testFilesWithoutATwinAreExcluded() {
        let groups = DuplicateGrouping.groups(
            files: [file(id: "only", name: "ONLY.HEIC")],
            definition: DuplicateRuleSelection.default.definition
        )
        XCTAssertTrue(groups.isEmpty)
    }

    /// The header names the group so the user can tell one from the next while scrolling.
    func testGroupTitleNamesTheFileAndTheCopyCount() {
        let groups = DuplicateGrouping.groups(
            files: [
                file(id: "a1", name: "A.HEIC"),
                file(id: "a2", name: "A.HEIC"),
                file(id: "a3", name: "A.HEIC")
            ],
            definition: DuplicateRuleSelection.default.definition
        )

        XCTAssertEqual(groups[0].title, "A.HEIC — 3 copies")
    }

    /// Changing the rule changes the grouping, which is the whole point of making it
    /// configurable.
    func testARelaxedRuleGroupsFilesTheStrictRuleSeparates() throws {
        let files = [
            file(id: "1", name: "A.HEIC", size: 1_000),
            file(id: "2", name: "A.HEIC", size: 2_000)
        ]

        let strict = DuplicateGrouping.groups(
            files: files,
            definition: DuplicateRuleSelection.default.definition
        )
        XCTAssertTrue(strict.isEmpty, "Different sizes are not duplicates under the default.")

        let relaxed = try XCTUnwrap(DuplicateRuleSelection(fields: [.name, .kind]))
        let grouped = DuplicateGrouping.groups(files: files, definition: relaxed.definition)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped[0].members.count, 2)
    }
}
