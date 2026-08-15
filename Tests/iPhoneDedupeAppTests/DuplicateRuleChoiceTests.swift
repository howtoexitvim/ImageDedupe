import DeduperCore
import Foundation
import XCTest

@testable import iPhoneDedupeApp

/// The user picks which fields decide that two files are duplicates. Since that choice
/// drives an irreversible delete, these cover the parts that must not go wrong: the plan
/// actually follows the choice, an unsafe choice cannot be applied, and a pending delete
/// cannot outlive the rule it was planned under.
@MainActor
final class DuplicateRuleChoiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "duplicate-rule-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeViewModel(
        files: [DeviceMediaFile] = []
    ) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel(
            duplicateRulePreferences: DuplicateRulePreferences(defaults: defaults)
        )
        if !files.isEmpty {
            viewModel.allItems = files.map {
                MediaBrowserViewModel.MediaItem(model: $0, token: .fixture())
            }
            viewModel.recomputeDuplicatePlanForTesting()
            viewModel.refreshVisibleOrder()
        }
        return viewModel
    }

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

    func testTheDefaultRuleIsTheConservativeOne() {
        XCTAssertEqual(makeViewModel().duplicateRule, .default)
    }

    /// Changing the rule must recompute the plan immediately, or Duplicates would show
    /// results from the previous rule.
    func testChangingTheRuleRecomputesTheDuplicatePlan() {
        let viewModel = makeViewModel(files: [
            file(id: "1", name: "A.HEIC", size: 1_000),
            file(id: "2", name: "A.HEIC", size: 2_000)
        ])

        XCTAssertTrue(
            viewModel.duplicatePlan.delete.isEmpty,
            "Different sizes are not duplicates under Name+Kind+Size."
        )

        viewModel.setDuplicateRule(DuplicateRuleSelection(fields: [.name, .kind]))

        XCTAssertEqual(viewModel.duplicatePlan.delete.map(\.id), ["2"])
    }

    /// Every field can be unticked, including Name, and the rule can be emptied.
    ///
    /// The floor was removed after measuring the real catalog: Name alone marked exactly
    /// the same single file as Name+Kind+Size. What guards the destructive step is the
    /// delete confirmation naming the files it will remove, not a restriction on the view.
    func testAnyFieldCanBeUntickedIncludingName() {
        let viewModel = makeViewModel()

        viewModel.toggleDuplicateRuleField(.name)
        XCTAssertFalse(viewModel.isDuplicateRuleFieldSelected(.name))
        XCTAssertEqual(viewModel.duplicateRule.fields, [.kind, .size])

        viewModel.toggleDuplicateRuleField(.kind)
        viewModel.toggleDuplicateRuleField(.size)
        XCTAssertTrue(viewModel.duplicateRule.fields.isEmpty)
    }

    /// An empty rule groups nothing rather than grouping everything, which would be the
    /// dangerous reading of "no fields".
    func testAnEmptyRuleGroupsNothing() {
        let viewModel = makeViewModel(files: [
            file(id: "1", name: "A.HEIC"),
            file(id: "2", name: "A.HEIC")
        ])
        XCTAssertEqual(viewModel.duplicatePlan.delete.count, 1)

        for field in viewModel.duplicateRule.fields {
            viewModel.toggleDuplicateRuleField(field)
        }

        XCTAssertTrue(viewModel.duplicatePlan.delete.isEmpty)
    }

    /// Matching on Name alone is what the user asked for, and it must be reachable in one
    /// step from the default.
    func testNameOnlyIsReachableAndGroupsSameNamedFiles() {
        let viewModel = makeViewModel(files: [
            file(id: "1", name: "A.HEIC", size: 1_000),
            file(id: "2", name: "A.HEIC", size: 2_000)
        ])

        viewModel.setDuplicateRule(DuplicateRuleSelection(fields: [.name]))

        XCTAssertEqual(viewModel.duplicatePlan.delete.map(\.id), ["2"])
    }

    func testTogglingAFieldOnAndOffReturnsTheOriginalRule() {
        let viewModel = makeViewModel()
        let before = viewModel.duplicateRule

        viewModel.toggleDuplicateRuleField(.timestamp)
        XCTAssertNotEqual(viewModel.duplicateRule, before)

        viewModel.toggleDuplicateRuleField(.timestamp)
        XCTAssertEqual(viewModel.duplicateRule, before)
    }

    func testTheChosenRuleIsRememberedAcrossLaunches() {
        let first = makeViewModel()
        first.toggleDuplicateRuleField(.timestamp)
        let chosen = first.duplicateRule

        XCTAssertEqual(makeViewModel().duplicateRule, chosen)
    }

    /// A pending delete freezes a specific set of files, chosen under a specific rule.
    /// Changing the rule changes what "duplicate" means, so that snapshot must not survive
    /// — otherwise the confirmation would describe one set and delete another.
    func testChangingTheRuleDiscardsAPendingDeleteSnapshot() {
        let viewModel = makeViewModel(files: [
            file(id: "1", name: "A.HEIC"),
            file(id: "2", name: "A.HEIC")
        ])
        viewModel.toggleActionSelection(withID: "2")
        viewModel.requestDeleteConfirmation()
        XCTAssertNotNil(viewModel.pendingDeleteSnapshot)

        viewModel.toggleDuplicateRuleField(.timestamp)

        XCTAssertNil(
            viewModel.pendingDeleteSnapshot,
            "A delete planned under the old rule must not survive the rule changing."
        )
    }
}
