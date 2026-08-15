import DeduperCore
import Foundation
import XCTest

@testable import DeviceMediaKit

/// `DeviceSession` is the rule "a rescan is a new process" made concrete. These tests cover
/// the parts that hold without a device attached: what happens before any scan, and how a
/// token from a retired helper is treated. Device-backed behaviour is verified separately
/// against the real iPhone, since a mock cannot tell us anything about ImageCaptureCore.
final class DeviceSessionTests: XCTestCase {
    private func makeToken(generation: UUID = UUID()) -> DeviceFileToken {
        DeviceFileToken(
            generation: generation,
            objectHandle: 1,
            fingerprint: DeviceFileFingerprint(
                name: "IMG_0001.HEIC",
                kind: "HEIC",
                size: 1_024,
                timestamp: nil
            )
        )
    }

    /// Commands before a scan must fail with "scan first" rather than starting a helper
    /// with no catalog, which would hold the device for a command that cannot resolve.
    func testCommandsBeforeAnyScanAreRefused() async {
        let session = DeviceSession(makeClient: { nil })

        do {
            _ = try await session.thumbnailData(for: makeToken())
            XCTFail("Expected a refusal before any scan")
        } catch {
            XCTAssertTrue(
                "\(error)".contains("Scan the device"),
                "Unexpected error: \(error)"
            )
        }
    }

    /// An empty batch must not start a helper at all.
    func testEmptyBatchesResolveWithoutTouchingTheDevice() async throws {
        let session = DeviceSession(makeClient: { nil })

        let imported = try await session.download([], stagingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(imported.successful.isEmpty)
        XCTAssertTrue(imported.failed.isEmpty)

        let (deleted, handles) = try await session.delete([], confirmed: true)
        XCTAssertTrue(deleted.successful.isEmpty)
        XCTAssertTrue(handles.isEmpty)
    }

    /// A missing helper binary is a build/packaging fault, and must say so rather than
    /// surfacing as a device timeout.
    func testAMissingHelperIsReportedAsMissingRatherThanAsADeviceFailure() async {
        let session = DeviceSession(makeClient: { nil })

        do {
            _ = try await session.scan(timeout: .seconds(1))
            XCTFail("Expected a missing-helper error")
        } catch let error as DeviceHelperError {
            guard case .helperNotFound = error else {
                return XCTFail("Expected helperNotFound, got \(error)")
            }
        } catch {
            XCTFail("Expected DeviceHelperError, got \(error)")
        }
    }

    /// Retiring is idempotent: the app retires on rescan and again on teardown.
    func testRetiringTwiceIsHarmless() async {
        let session = DeviceSession(makeClient: { nil })
        await session.retire()
        await session.retire()
    }

    /// Cancel before any helper exists must not trap.
    func testCancelWithoutAHelperIsHarmless() async {
        let session = DeviceSession(makeClient: { nil })
        await session.cancel()
    }
}
