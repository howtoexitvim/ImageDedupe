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

        viewModel.setDuplicateRule(XCTUnwrap2(DuplicateRuleSelection(fields: [.name, .kind])))

        XCTAssertEqual(viewModel.duplicatePlan.delete.map(\.id), ["2"])
    }

    /// The safety floor, enforced where the user can reach it.
    ///
    /// Unticking Name from Name+Kind+Size would leave Kind+Size, which groups every file of
    /// the same type and byte count — the pairing that looks reasonable and is not. The
    /// rule must stay exactly as it was.
    func testAnUnsafeSelectionIsRefusedAndTheRuleIsUnchanged() {
        let viewModel = makeViewModel()
        let before = viewModel.duplicateRule

        viewModel.toggleDuplicateRuleField(.name)

        XCTAssertEqual(
            viewModel.duplicateRule,
            before,
            "Removing the only content-identifying field must be refused."
        )
        XCTAssertFalse(
            viewModel.canToggleDuplicateRuleField(.name),
            "The checkbox must be disabled, so the refusal is visible before it is needed."
        )
    }

    /// The floor stops a rule becoming unusable, but must not block a legitimate one:
    /// Name+Size still identifies a file, so unticking Kind is allowed.
    func testASafeRelaxationIsStillAllowed() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.canToggleDuplicateRuleField(.kind))
        viewModel.toggleDuplicateRuleField(.kind)

        XCTAssertEqual(viewModel.duplicateRule.fields, [.name, .size])
    }

    /// Reduced to the minimum, the last remaining fields lock so the rule cannot be emptied.
    func testTheFinalTwoFieldsCannotBeRemoved() {
        let viewModel = makeViewModel()
        viewModel.toggleDuplicateRuleField(.kind)
        XCTAssertEqual(viewModel.duplicateRule.fields, [.name, .size])

        XCTAssertFalse(viewModel.canToggleDuplicateRuleField(.name))
        XCTAssertFalse(viewModel.canToggleDuplicateRuleField(.size))
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

/// `XCTUnwrap` is throwing, which does not suit a non-throwing test body.
private func XCTUnwrap2<T>(_ value: T?) -> T {
    guard let value else {
        preconditionFailure("Expected a non-nil value")
    }
    return value
}
