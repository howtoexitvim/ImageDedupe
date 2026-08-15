import XCTest

@testable import DeduperCore

/// The user chooses which fields decide that two files are duplicates. This is the model
/// behind that choice, and it carries a safety floor: the rule drives an irreversible
/// delete, so a selection that would group unrelated files must not be expressible.
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

    // MARK: - The safety floor

    /// Name alone, size alone, or date alone will each group unrelated files: an iPhone
    /// reuses names like IMG_0001.HEIC after a reset, thousands of files share a size, and
    /// a burst shares a timestamp. Since the rule drives a delete, at least two fields must
    /// participate, and one of them must actually identify content.
    func testASingleFieldIsNotAValidRule() {
        XCTAssertNil(DuplicateRuleSelection(fields: [.name]))
        XCTAssertNil(DuplicateRuleSelection(fields: [.size]))
        XCTAssertNil(DuplicateRuleSelection(fields: [.timestamp]))
    }

    func testAnEmptySelectionIsNotAValidRule() {
        XCTAssertNil(DuplicateRuleSelection(fields: []))
    }

    /// Kind plus size is the pairing that looks reasonable and is not: every 4 MB HEIC on
    /// the device would become one duplicate group.
    func testKindAndSizeAloneIsRefused() {
        XCTAssertNil(DuplicateRuleSelection(fields: [.kind, .size]))
    }

    func testTheDefaultRuleIsTheConservativeOne() {
        let selection = DuplicateRuleSelection.default
        XCTAssertEqual(selection.fields, [.name, .kind, .size])
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
    func testDroppingSizeFindsSameNamedFilesOfDifferentSize() throws {
        let selection = try XCTUnwrap(DuplicateRuleSelection(fields: [.name, .kind]))
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
    func testFilesMissingARequiredFieldAreNeverGrouped() throws {
        let selection = try XCTUnwrap(DuplicateRuleSelection(fields: [.name, .timestamp]))
        let plan = DuplicatePlanner.plan(
            files: [
                file(id: "1", name: "IMG_0001.HEIC", timestamp: nil),
                file(id: "2", name: "IMG_0001.HEIC", timestamp: nil)
            ],
            definition: selection.definition
        )

        XCTAssertTrue(plan.delete.isEmpty, "Absent values must not match each other.")
    }

    func testDurationParticipatesWhenSelected() throws {
        let selection = try XCTUnwrap(DuplicateRuleSelection(fields: [.name, .duration]))
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
    func testFieldOrderDoesNotChangeTheRule() throws {
        let one = try XCTUnwrap(DuplicateRuleSelection(fields: [.name, .kind, .size]))
        let other = try XCTUnwrap(DuplicateRuleSelection(fields: [.size, .name, .kind]))
        XCTAssertEqual(one.fields, other.fields)
        XCTAssertEqual(one.definition, other.definition)
    }

    // MARK: - Persistence

    func testASelectionSurvivesARoundTripThroughItsStoredForm() throws {
        let selection = try XCTUnwrap(DuplicateRuleSelection(fields: [.name, .kind, .timestamp]))
        let restored = DuplicateRuleSelection(storedValue: selection.storedValue)
        XCTAssertEqual(restored, selection)
    }

    /// A stored value from a future version, or a corrupted one, must fall back to the
    /// conservative default rather than to something looser.
    func testAnUnreadableStoredValueFallsBackToTheDefault() {
        XCTAssertEqual(DuplicateRuleSelection(storedValue: "nonsense"), .default)
        XCTAssertEqual(DuplicateRuleSelection(storedValue: ""), .default)
        XCTAssertEqual(DuplicateRuleSelection(storedValue: "size"), .default)
    }
}
