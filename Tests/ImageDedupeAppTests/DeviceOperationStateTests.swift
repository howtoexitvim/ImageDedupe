import XCTest
@testable import ImageDedupeApp

/// Phase 6: one operation state machine and one session generation.
///
/// Two separate hazards, both invisible until they corrupt something:
///
/// - Scan, import, and delete could previously overlap or double-submit, because each
///   guarded itself with its own ad-hoc flag (or, for import and delete, no flag at all).
/// - A thumbnail or metadata result from an old scan could arrive after a new scan and
///   mutate the current session's caches.
final class DeviceOperationStateTests: XCTestCase {
    // MARK: - Admission

    func testIdleAdmitsEveryOperation() {
        let state = DeviceOperationState()
        XCTAssertTrue(state.canBegin(.scanning))
        XCTAssertTrue(state.canBegin(.importing))
        XCTAssertTrue(state.canBegin(.deleting))
    }

    func testBeginningAnOperationMakesItCurrent() {
        var state = DeviceOperationState()
        XCTAssertTrue(state.begin(.scanning))
        XCTAssertEqual(state.current, .scanning)
        XCTAssertTrue(state.isBusy)
    }

    func testTheSameOperationCannotDoubleSubmit() {
        var state = DeviceOperationState()
        XCTAssertTrue(state.begin(.importing))
        XCTAssertFalse(state.begin(.importing), "a second import must be rejected")
        XCTAssertEqual(state.current, .importing)
    }

    /// The dangerous case: a delete starting while an import is still running.
    func testADifferentOperationCannotInterleave() {
        var state = DeviceOperationState()
        XCTAssertTrue(state.begin(.importing))

        XCTAssertFalse(state.begin(.deleting))
        XCTAssertFalse(state.begin(.scanning))
        XCTAssertEqual(state.current, .importing)
    }

    func testFinishingReturnsToIdleAndAdmitsAgain() {
        var state = DeviceOperationState()
        _ = state.begin(.scanning)
        state.finish()

        XCTAssertEqual(state.current, .idle)
        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.begin(.deleting))
    }

    func testFailingReturnsToIdleSoTheUserCanRetry() {
        var state = DeviceOperationState()
        _ = state.begin(.importing)
        state.fail()

        XCTAssertEqual(state.current, .idle)
        XCTAssertTrue(state.begin(.importing))
    }

    func testFinishingWhenIdleIsHarmless() {
        var state = DeviceOperationState()
        state.finish()
        XCTAssertEqual(state.current, .idle)
    }

    // MARK: - Session generation

    func testGenerationStartsStable() {
        let state = DeviceOperationState()
        XCTAssertEqual(state.generation, state.generation)
    }

    /// A new scan opens a new session, so results from the previous one must be ignorable.
    func testBeginningAScanAdvancesTheGeneration() {
        var state = DeviceOperationState()
        let before = state.generation
        _ = state.begin(.scanning)

        XCTAssertNotEqual(state.generation, before)
    }

    func testImportAndDeleteDoNotAdvanceTheGeneration() {
        var state = DeviceOperationState()
        _ = state.begin(.scanning)
        state.finish()
        let afterScan = state.generation

        _ = state.begin(.importing)
        state.finish()
        _ = state.begin(.deleting)
        state.finish()

        XCTAssertEqual(
            state.generation,
            afterScan,
            "only a new scan invalidates cached thumbnails and metadata"
        )
    }

    func testResultsFromTheCurrentGenerationAreAccepted() {
        var state = DeviceOperationState()
        _ = state.begin(.scanning)

        XCTAssertTrue(state.isCurrent(generation: state.generation))
    }

    func testResultsFromAPreviousGenerationAreRejected() {
        var state = DeviceOperationState()
        _ = state.begin(.scanning)
        let stale = state.generation
        state.finish()
        _ = state.begin(.scanning)

        XCTAssertFalse(
            state.isCurrent(generation: stale),
            "a result from the previous scan must not mutate the new session"
        )
    }

    func testGenerationKeepsAdvancingAcrossManyScans() {
        var state = DeviceOperationState()
        var seen = Set<Int>()
        for _ in 0..<50 {
            _ = state.begin(.scanning)
            seen.insert(state.generation)
            state.finish()
        }
        XCTAssertEqual(seen.count, 50, "each scan must get a distinct generation")
    }

    // MARK: - Status reporting

    func testBusyDescriptionNamesTheRunningOperation() {
        var state = DeviceOperationState()
        _ = state.begin(.deleting)
        XCTAssertEqual(state.current.verb, "Deleting")
    }

    func testEveryOperationHasAVerb() {
        for operation in DeviceOperationState.Operation.allCases {
            XCTAssertFalse(operation.verb.isEmpty)
        }
    }
}
