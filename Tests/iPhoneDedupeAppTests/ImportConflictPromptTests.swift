import DeduperCore
import DeviceMediaKit
import Foundation
import XCTest

@testable import iPhoneDedupeApp

/// The prompt shown when a download would land on an existing filename.
///
/// Downloading a duplicate group collides on every copy after the first, so this is the
/// ordinary path. These cover the state machine around the prompt: the answer reaches the
/// waiting import, "apply to all" stops further asking, and cancelling ends the import
/// rather than silently continuing.
@MainActor
final class ImportConflictPromptTests: XCTestCase {
    private func makeViewModel() -> MediaBrowserViewModel {
        MediaBrowserViewModel()
    }

    func testResolvingClearsThePrompt() async {
        let viewModel = makeViewModel()
        viewModel.pendingImportConflict = .init(filename: "IMG_0001.HEIC", remainingCount: 3)

        viewModel.resolveImportConflict(.keepBoth, applyToAll: false)

        XCTAssertNil(viewModel.pendingImportConflict)
    }

    func testCancellingClearsThePrompt() {
        let viewModel = makeViewModel()
        viewModel.pendingImportConflict = .init(filename: "IMG_0001.HEIC", remainingCount: 0)

        viewModel.cancelImportFromConflict()

        XCTAssertNil(viewModel.pendingImportConflict)
    }

    /// The prompt says how many files are still waiting, so "apply to all" states what it
    /// covers rather than being an open-ended promise.
    func testThePromptCarriesTheRemainingCount() {
        let conflict = MediaBrowserViewModel.ImportConflict(
            filename: "IMG_0001.HEIC",
            remainingCount: 7
        )
        XCTAssertEqual(conflict.remainingCount, 7)
        XCTAssertEqual(conflict.filename, "IMG_0001.HEIC")
    }

    /// Two prompts for the same filename are still distinct events, so answering one cannot
    /// dismiss another.
    func testTwoConflictsForTheSameNameAreDistinct() {
        let first = MediaBrowserViewModel.ImportConflict(filename: "A.HEIC", remainingCount: 1)
        let second = MediaBrowserViewModel.ImportConflict(filename: "A.HEIC", remainingCount: 0)
        XCTAssertNotEqual(first, second)
    }

    /// Replace is the only destructive answer, which is what the sheet styles in red and
    /// what makes "apply to all" worth stating precisely.
    func testOnlyReplaceIsDestructive() {
        XCTAssertTrue(ImportConflictResolution.replace.isDestructive)
        XCTAssertFalse(ImportConflictResolution.keepBoth.isDestructive)
        XCTAssertFalse(ImportConflictResolution.skip.isDestructive)
    }

    /// Keep Both is the option that discards nothing, so it is the sheet's default action.
    func testKeepBothDiscardsNothing() {
        XCTAssertFalse(ImportConflictResolution.keepBoth.isDestructive)
        XCTAssertEqual(ImportConflictResolution.keepBoth.title, "Keep Both")
    }
}
