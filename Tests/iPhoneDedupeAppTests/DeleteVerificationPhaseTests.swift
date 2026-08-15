import AppKit
import DeduperCore
import DeviceMediaKit
import Foundation
import XCTest
@testable import iPhoneDedupeApp

/// Post-delete verification used to run under the `Deleting — 1 of 1` label with no
/// cancellation channel of its own, so a 180-second device-service wait looked like an
/// unbounded destructive operation and Cancel left the UI at `Canceling delete…` forever.
@MainActor
final class DeleteVerificationPhaseTests: XCTestCase {

    // MARK: - Visible phase

    func testVerificationIsItsOwnVisiblePhaseRatherThanDeleting() {
        var progress = MediaOperationProgress(kind: .deleting, totalItems: 1)
        progress.apply(DeviceBatchProgress(
            completedItems: 1,
            totalItems: 1,
            currentFilename: "IMG_0001.HEIC",
            fractionCompleted: 1
        ))
        XCTAssertEqual(progress.detail, "Deleting — 1 of 1")

        progress.beginVerification()

        XCTAssertEqual(progress.phase, .verifying)
        XCTAssertEqual(progress.detail, "Verifying deletion…")
        XCTAssertTrue(progress.canCancel, "Verification must remain cancelable.")
    }

    func testCancelingDuringVerificationReadsAsVerificationNotDeletion() {
        var progress = MediaOperationProgress(kind: .deleting, totalItems: 1)
        progress.beginVerification()

        XCTAssertTrue(progress.requestCancellation())

        XCTAssertEqual(progress.detail, "Canceling verification…")
        XCTAssertFalse(progress.canCancel)
    }

    // MARK: - Cancellation is bounded

    func testCancelSettlesVerificationEvenWhenTheScanNeverCompletes() async {
        let viewModel = makeViewModel(verificationScan: { _ in
            // Models ImageCaptureCore never acknowledging: sleeps far past any bounded wait.
            try await Task.sleep(for: .seconds(600))
            throw DeviceGatewayError.timeout("iPhone media catalog")
        })
        let snapshot = snapshot(named: "IMG_9001.HEIC")

        viewModel.startDeleteVerificationForTesting(
            snapshot: snapshot,
            summary: DeviceGatewayDeleteSummary()
        )
        await waitUntil { viewModel.operationProgress?.phase == .verifying }

        viewModel.cancelCurrentOperation()

        await waitUntil { !viewModel.isDeviceBusy }
        XCTAssertNil(viewModel.operationProgress, "Cancel must clear the progress chrome.")
        XCTAssertFalse(
            viewModel.status.contains("Canceling"),
            "Cancel must settle to a terminal status, not remain at Canceling: \(viewModel.status)"
        )
    }

    func testCanceledVerificationNeverRemovesARowOrClaimsSuccess() async {
        let viewModel = makeViewModel(verificationScan: { _ in
            try await Task.sleep(for: .seconds(600))
            throw DeviceGatewayError.timeout("iPhone media catalog")
        })
        let item = mediaItem(named: "IMG_9002.HEIC")
        viewModel.allItems = [item]
        viewModel.refreshVisibleOrder()

        viewModel.startDeleteVerificationForTesting(
            snapshot: snapshot(named: item.model.name, token: item.token),
            summary: DeviceGatewayDeleteSummary(successful: [item.token])
        )
        await waitUntil { viewModel.operationProgress?.phase == .verifying }
        viewModel.cancelCurrentOperation()
        await waitUntil { !viewModel.isDeviceBusy }

        XCTAssertEqual(
            viewModel.allItems.count,
            1,
            "Only reconciliation against a fresh catalog may remove a row."
        )
        let audit = viewModel.operationHistory.first?.deleteAudit
        XCTAssertEqual(audit?.verificationState, .pending)
        XCTAssertEqual(audit?.items.first?.outcome, .verificationPending)
    }

    func testLateVerificationResultAfterCancelCannotMutateTheViewModel() async {
        let release = AsyncGate()
        let viewModel = makeViewModel(verificationScan: { [item = mediaItem(named: "IMG_9003.HEIC")] _ in
            await release.wait()
            return DeviceCatalogSnapshot(
                generation: UUID(),
                deviceName: "Late iPhone",
                deviceIdentityHash: nil,
                files: [DeviceCatalogFile(model: item.model, token: item.token)]
            )
        })
        viewModel.deviceName = "Original iPhone"

        viewModel.startDeleteVerificationForTesting(
            snapshot: snapshot(named: "IMG_9003.HEIC"),
            summary: DeviceGatewayDeleteSummary()
        )
        await waitUntil { viewModel.operationProgress?.phase == .verifying }
        viewModel.cancelCurrentOperation()
        await waitUntil { !viewModel.isDeviceBusy }

        let historyCountAfterCancel = viewModel.operationHistory.count
        await release.open()
        for _ in 0..<200 { await Task.yield() }

        XCTAssertEqual(viewModel.deviceName, "Original iPhone", "A late catalog must not be applied.")
        XCTAssertEqual(viewModel.operationHistory.count, historyCountAfterCancel)
    }

    // MARK: - Honest completion when Delete was never submitted

    func testDeleteThatCouldNotBeSubmittedFinishesWithoutAMisleadingDeletePhase() async {
        var verificationScanCount = 0
        let viewModel = makeViewModel(verificationScan: { _ in
            verificationScanCount += 1
            throw DeviceGatewayError.noDevice
        })
        let snapshot = snapshot(named: "IMG_9004.HEIC")

        viewModel.startDeleteVerificationForTesting(
            snapshot: snapshot,
            summary: DeviceGatewayDeleteSummary(failed: [
                DeviceOperationFailure(
                    token: snapshot.items[0].token,
                    filename: snapshot.items[0].filename,
                    reason: DeviceGatewayError.noDevice.localizedDescription
                )
            ])
        )
        await waitUntil { !viewModel.isDeviceBusy }

        XCTAssertEqual(
            verificationScanCount,
            0,
            "Delete was provably never submitted, so no verification scan should run."
        )
        XCTAssertNil(viewModel.operationProgress)
        let audit = viewModel.operationHistory.first?.deleteAudit
        XCTAssertEqual(audit?.verificationState, .pending)
        XCTAssertNotEqual(audit?.items.first?.outcome, .confirmedRemoved)
    }

    // MARK: - Retry Verification is scan-only

    func testRetryVerificationRunsAScanAndNeverResubmitsDelete() async {
        var verificationScanCount = 0
        // The first verification fails, leaving the audit pending — the only state in which
        // Retry Verification is offered.
        let viewModel = makeViewModel(verificationScan: { _ in
            verificationScanCount += 1
            throw DeviceGatewayError.timeout("iPhone media catalog")
        })
        let snapshot = snapshot(named: "IMG_9005.HEIC")
        viewModel.startDeleteVerificationForTesting(
            snapshot: snapshot,
            summary: DeviceGatewayDeleteSummary(successful: [snapshot.items[0].token])
        )
        await waitUntil { !viewModel.isDeviceBusy }
        XCTAssertEqual(verificationScanCount, 1)
        XCTAssertEqual(viewModel.operationHistory.first?.deleteAudit?.verificationState, .pending)

        guard let recordID = viewModel.operationHistory.first?.id else {
            return XCTFail("Expected a persisted delete record")
        }
        viewModel.retryDeleteVerification(recordID: recordID)
        await waitUntil { !viewModel.isDeviceBusy }

        XCTAssertEqual(verificationScanCount, 2, "Retry must perform exactly one more scan.")
        XCTAssertEqual(
            viewModel.deleteSubmissionCountForTesting,
            0,
            "Retry Verification must never resubmit a delete."
        )
    }

    // MARK: - Helpers

    private func makeViewModel(
        verificationScan: @escaping MediaBrowserViewModel.VerificationScan
    ) -> MediaBrowserViewModel {
        // A private per-test directory, so the store's permission hardening applies to a
        // directory the test owns rather than to the shared temporary directory.
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-verification-\(UUID().uuidString)", isDirectory: true)
        let historyURL = directoryURL.appendingPathComponent("history.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: directoryURL) }
        return MediaBrowserViewModel(
            operationResultStore: OperationResultStore(fileURL: historyURL),
            verificationScan: verificationScan
        )
    }

    private func mediaItem(named name: String) -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: DeviceMediaFile(
                id: "id-\(name)",
                name: name,
                kind: "HEIC",
                size: 1_000,
                timestamp: nil,
                width: nil,
                height: nil
            ),
            token: .fixture()
        )
    }

    private func snapshot(
        named name: String,
        token: DeviceFileToken = .fixture()
    ) -> DeletePlanSnapshot {
        DeletePlanSnapshot(
            deviceName: "Test iPhone",
            items: [
                DeletePlanSnapshot.Item(token: token, filename: name, kind: "HEIC", size: 1_000)
            ]
        )
    }

    private func waitUntil(
        attempts: Int = 5_000,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Condition was not satisfied in time", file: file, line: line)
    }
}

/// A gate a fake scan can block on until the test deliberately releases it.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
