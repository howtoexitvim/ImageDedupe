import DeduperCore
import Foundation
import XCTest

@testable import iPhoneDedupeApp

/// What the inspector says about the selected file's duplicate status.
///
/// The tile badges are a glance; the inspector is where the user decides. It therefore has
/// to say the same thing in words: whether this copy is the one being kept, or one of the
/// copies Delete would remove, and how many copies exist.
@MainActor
final class DuplicateInspectorStatusTests: XCTestCase {
    /// An isolated defaults suite. The duplicate rule persists, so without this a rule set
    /// by another test leaks in and these assertions describe the wrong rule.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "inspector-status-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func file(id: String, name: String) -> DeviceMediaFile {
        DeviceMediaFile(
            id: id,
            name: name,
            kind: "HEIC",
            size: 1_000,
            timestamp: "2026-08-15T00:00:00.000Z",
            width: nil,
            height: nil
        )
    }

    private func viewModel(_ files: [DeviceMediaFile]) -> MediaBrowserViewModel {
        let viewModel = MediaBrowserViewModel(
            duplicateRulePreferences: DuplicateRulePreferences(defaults: defaults)
        )
        viewModel.allItems = files.map {
            MediaBrowserViewModel.MediaItem(model: $0, token: .fixture())
        }
        viewModel.recomputeDuplicatePlanForTesting()
        return viewModel
    }

    func testAFileWithNoTwinReportsNoDuplicate() {
        let model = viewModel([file(id: "solo", name: "SOLO.HEIC")])
        XCTAssertEqual(model.duplicateStatus(forItemID: "solo"), .notDuplicated)
    }

    /// The blue-sealed copy, stated in words so the inspector agrees with the badge.
    func testTheKeptCopyReportsThatItIsKept() {
        let model = viewModel([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC")
        ])

        XCTAssertEqual(model.duplicateStatus(forItemID: "a1"), .keptCopy(copies: 2))
    }

    /// The orange-triangled copy: what Delete would remove.
    func testARedundantCopyReportsThatItWouldBeRemoved() {
        let model = viewModel([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "a3", name: "A.HEIC")
        ])

        XCTAssertEqual(model.duplicateStatus(forItemID: "a3"), .redundantCopy(copies: 3))
    }

    /// The copy count is the group's, not the catalog's, so the user can see how many
    /// copies of *this* file exist.
    func testTheCountIsTheGroupsOwn() {
        let model = viewModel([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC"),
            file(id: "b2", name: "B.HEIC"),
            file(id: "b3", name: "B.HEIC")
        ])

        XCTAssertEqual(model.duplicateStatus(forItemID: "a2"), .redundantCopy(copies: 2))
        XCTAssertEqual(model.duplicateStatus(forItemID: "b2"), .redundantCopy(copies: 3))
    }

    /// The wording must state the consequence, since this is what the user reads before
    /// deleting.
    func testTheDescriptionsSayWhatWillHappen() {
        XCTAssertTrue(
            MediaBrowserViewModel.DuplicateStatus.keptCopy(copies: 3)
                .detail.localizedCaseInsensitiveContains("kept")
        )
        XCTAssertTrue(
            MediaBrowserViewModel.DuplicateStatus.redundantCopy(copies: 3)
                .detail.localizedCaseInsensitiveContains("remove")
        )
    }

    /// Changing the rule changes the status, so the inspector cannot show a verdict from a
    /// rule the user has since changed.
    func testTheStatusFollowsTheCurrentRule() {
        // Same name, different sizes: not duplicates under Name+Kind+Size, duplicates once
        // Size is unticked.
        let model = viewModel([
            DeviceMediaFile(
                id: "1", name: "A.HEIC", kind: "HEIC", size: 1_000,
                timestamp: "2026-08-15T00:00:00.000Z", width: nil, height: nil
            ),
            DeviceMediaFile(
                id: "2", name: "A.HEIC", kind: "HEIC", size: 2_000,
                timestamp: "2026-08-15T00:00:00.000Z", width: nil, height: nil
            )
        ])

        XCTAssertEqual(
            model.duplicateStatus(forItemID: "2"),
            .notDuplicated,
            "Different sizes are not duplicates under the default rule."
        )

        model.setDuplicateRule(DuplicateRuleSelection(fields: [.name, .kind]))

        XCTAssertEqual(model.duplicateStatus(forItemID: "2"), .redundantCopy(copies: 2))
    }
}
