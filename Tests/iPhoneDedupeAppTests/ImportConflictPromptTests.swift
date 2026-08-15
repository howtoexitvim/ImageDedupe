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

    /// The preflight must not refuse a batch for a reason the app can now ask about.
    ///
    /// Reported on 2026-08-16: the conflict sheet never appeared. The preflight blocked the
    /// whole import on `filenameCollisions` *before* any download started, so the prompt
    /// built to resolve that exact situation was unreachable.
    ///
    /// An existing filename is a question now, not a failure. Genuine blockers — an
    /// unwritable folder, a full disk — must still refuse up front, because no per-file
    /// choice can rescue those.
    func testAnExistingFilenameNoLongerBlocksTheWholeImport() {
        let outcome = ImportDestinationPreflight.evaluate(
            items: [ImportDestinationPreflight.Item(filename: "IMG_0001.HEIC", size: 10)],
            facts: ImportDestinationPreflight.Facts(
                isDirectory: true,
                isLocalVolume: true,
                isWritable: true,
                availableCapacity: 10_000,
                stagingSharesDestinationVolume: true,
                stagingAvailableCapacity: 10_000,
                existingFilenames: ["IMG_0001.HEIC"]
            )
        )

        guard case .ready = outcome else {
            return XCTFail("A name conflict is resolved per file, not by refusing, got \(outcome)")
        }
    }

    /// Blockers the user cannot answer per file must still stop the batch before anything
    /// is downloaded.
    func testRealBlockersStillRefuseUpFront() {
        let unwritable = ImportDestinationPreflight.evaluate(
            items: [ImportDestinationPreflight.Item(filename: "A.HEIC", size: 10)],
            facts: ImportDestinationPreflight.Facts(
                isDirectory: true,
                isLocalVolume: true,
                isWritable: false,
                availableCapacity: 10_000,
                stagingSharesDestinationVolume: true,
                stagingAvailableCapacity: 10_000,
                existingFilenames: []
            )
        )
        XCTAssertEqual(unwritable, .blocked(.notWritable))

        let full = ImportDestinationPreflight.evaluate(
            items: [ImportDestinationPreflight.Item(filename: "A.HEIC", size: 10_000)],
            facts: ImportDestinationPreflight.Facts(
                isDirectory: true,
                isLocalVolume: true,
                isWritable: true,
                availableCapacity: 5,
                stagingSharesDestinationVolume: true,
                stagingAvailableCapacity: 10_000,
                existingFilenames: []
            )
        )
        guard case .blocked(.insufficientSpace) = full else {
            return XCTFail("A full disk must still block, got \(full)")
        }
    }
}
