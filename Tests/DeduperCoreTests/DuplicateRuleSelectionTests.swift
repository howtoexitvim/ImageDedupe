import XCTest

@testable import DeduperCore

/// The user chooses which fields decide that two files are duplicates. Every combination is
/// permitted — a single field, or none — because a rule only changes what Duplicates shows.
/// The delete confirmation, which names the exact files it will remove, is what guards the
/// destructive step.
final class DuplicateRuleSelectionTests: XCTestCase {
    private func file(
        id: String,
        name: String,
        kind: String = "HEIC",
        size: Int64 = 1_000,
        timestamp: String? = "2026-08-15T00:00:00.000Z",
        duration: Double? = nil
    ) -> DeviceMediaFile {
        DeviceMediaFile(
            id: id,
            name: name,
            kind: kind,
            size: size,
            timestamp: timestamp,
            width: nil,
            height: nil,
            duration: duration
        )
    }

    // MARK: - Every combination is permitted

    /// The floor was removed at the user's direction, after measuring what the rules
    /// actually do to their catalog: on 3,955 files, Name alone marked exactly the same
    /// single file as Name+Kind+Size, so the name-collision risk that justified the floor
    /// did not exist in practice.
    ///
    /// A rule only changes what Duplicates *shows*. The delete confirmation, which names
    /// the exact files it will remove, is what guards the destructive step — and it is
    /// unchanged.
    func testASingleFieldIsAValidRule() {
        XCTAssertEqual(DuplicateRuleSelection(fields: [.name]).fields, [.name])
        XCTAssertEqual(DuplicateRuleSelection(fields: [.size]).fields, [.size])
        XCTAssertEqual(DuplicateRuleSelection(fields: [.timestamp]).fields, [.timestamp])
    }

    /// Selecting nothing is legal and simply groups nothing, rather than being rejected or
    /// silently reset.
    func testAnEmptySelectionGroupsNothing() {
        let selection = DuplicateRuleSelection(fields: [])
        XCTAssertTrue(selection.fields.isEmpty)

        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "A.HEIC"),
                file(id: "2", name: "A.HEIC")
            ],
            definition: selection.definition
        )
        XCTAssertTrue(plan.delete.isEmpty, "No fields means nothing is a duplicate.")
    }

    /// An empty rule must survive a round trip rather than being mistaken for "nothing
    /// stored" and reset to the default on the next launch.
    func testAnEmptySelectionSurvivesARoundTrip() {
        let empty = DuplicateRuleSelection(fields: [])
        XCTAssertTrue(DuplicateRuleSelection(storedValue: empty.storedValue).fields.isEmpty)
    }

    func testEveryFieldCanBeUntickedIncludingName() {
        var selection = DuplicateRuleSelection.default
        for field in selection.fields {
            selection = selection.toggling(field)
        }
        XCTAssertTrue(selection.fields.isEmpty)
    }

    func testTheDefaultRuleIsTheConservativeOne() {
        XCTAssertEqual(DuplicateRuleSelection.default.fields, [.name, .kind, .size])
    }

    // MARK: - Matching

    func testTheDefaultRuleGroupsOnlyIdenticalNameKindAndSize() {
        let selection = DuplicateRuleSelection.default
        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "IMG_0001.HEIC"),
                file(id: "2", name: "IMG_0001.HEIC"),
                file(id: "3", name: "IMG_0001.HEIC", size: 2_000)
            ],
            definition: selection.definition
        )

        XCTAssertEqual(plan.delete.map(\.id), ["2"], "Only the exact repeat is redundant.")
        XCTAssertEqual(Set(plan.keep.map(\.id)), ["1", "3"])
    }

    /// Relaxing the rule to name and kind finds a same-named file whose size changed, which
    /// is what the user asked for — a genuine duplicate that the strict rule misses.
    func testDroppingSizeFindsSameNamedFilesOfDifferentSize() {
        let selection = DuplicateRuleSelection(fields: [.name, .kind])
        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "IMG_0001.HEIC", size: 1_000),
                file(id: "2", name: "IMG_0001.HEIC", size: 2_000)
            ],
            definition: selection.definition
        )

        XCTAssertEqual(plan.delete.map(\.id), ["2"])
    }

    func testNameMatchingIgnoresCase() throws {
        let selection = DuplicateRuleSelection.default
        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "IMG_0001.HEIC"),
                file(id: "2", name: "img_0001.heic")
            ],
            definition: selection.definition
        )

        XCTAssertEqual(plan.delete.map(\.id), ["2"])
    }

    /// A file missing a field the rule needs is never grouped, so an absent timestamp
    /// cannot silently match another absent timestamp.
    func testFilesMissingARequiredFieldAreNeverGrouped() {
        let selection = DuplicateRuleSelection(fields: [.name, .timestamp])
        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "IMG_0001.HEIC", timestamp: nil),
                file(id: "2", name: "IMG_0001.HEIC", timestamp: nil)
            ],
            definition: selection.definition
        )

        XCTAssertTrue(plan.delete.isEmpty, "Absent values must not match each other.")
    }

    func testDurationParticipatesWhenSelected() {
        let selection = DuplicateRuleSelection(fields: [.name, .duration])
        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "CLIP.MOV", kind: "MOV", duration: 12.5),
                file(id: "2", name: "CLIP.MOV", kind: "MOV", duration: 12.5),
                file(id: "3", name: "CLIP.MOV", kind: "MOV", duration: 30.0)
            ],
            definition: selection.definition
        )

        XCTAssertEqual(plan.delete.map(\.id), ["2"])
    }

    /// Field order must not change the outcome, so ticking boxes in a different order
    /// cannot produce a different rule.
    func testFieldOrderDoesNotChangeTheRule() {
        let one = DuplicateRuleSelection(fields: [.name, .kind, .size])
        let other = DuplicateRuleSelection(fields: [.size, .name, .kind])
        XCTAssertEqual(one.fields, other.fields)
        XCTAssertEqual(one.definition, other.definition)
    }

    // MARK: - Persistence

    func testASelectionSurvivesARoundTripThroughItsStoredForm() {
        let selection = DuplicateRuleSelection(fields: [.name, .kind, .timestamp])
        let restored = DuplicateRuleSelection(storedValue: selection.storedValue)
        XCTAssertEqual(restored, selection)
    }

    /// A stored value from a future version, or a corrupted one, must fall back to the
    /// conservative default rather than to something looser.
    func testAnUnreadableStoredValueFallsBackToTheDefault() {
        XCTAssertEqual(DuplicateRuleSelection(storedValue: "nonsense"), .default)
        XCTAssertEqual(DuplicateRuleSelection(storedValue: ""), .default)
        // A legible single field is honoured rather than overridden.
        XCTAssertEqual(DuplicateRuleSelection(storedValue: "size").fields, [.size])
    }
}
