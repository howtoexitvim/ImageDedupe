import DeduperCore
@preconcurrency import ImageCaptureCore
import XCTest
@testable import DeviceMediaKit

/// Covers the device-session lifecycle regression found during physical-device testing on
/// 2026-08-15: a successful scan tore down the browsed device, so a later Delete reported
/// `No unlocked iPhone is available.` while Download still worked from its retained
/// `ICCameraFile`.
@MainActor
final class DeviceSessionLifecycleTests: XCTestCase {
    func testSuccessfulScanKeepsTheDeviceAvailableForLaterCommands() {
        let gateway = ImageCaptureDeviceGateway()
        let camera = LifecycleCameraDevice()

        gateway.deviceBrowser(ICDeviceBrowser(), didAdd: camera, moreComing: false)
        XCTAssertTrue(gateway.hasCommandDeviceForTesting)

        // ImageCaptureCore removes the browsed device once the browser stops. The gateway
        // must keep the successful session available for a later Delete.
        gateway.stopBrowsingForTesting()
        gateway.deviceBrowser(ICDeviceBrowser(), didRemove: camera, moreGoing: false)

        XCTAssertTrue(
            gateway.hasCommandDeviceForTesting,
            "A browser-stop removal after a successful catalog must not clear the command device."
        )
    }

    func testGenuineDisconnectAfterScanClearsTheCommandDevice() {
        let gateway = ImageCaptureDeviceGateway()
        let camera = LifecycleCameraDevice()

        gateway.deviceBrowser(ICDeviceBrowser(), didAdd: camera, moreComing: false)
        // No preceding `stopBrowsing`: this is a real unplug while the browser is running.
        gateway.deviceBrowser(ICDeviceBrowser(), didRemove: camera, moreGoing: false)

        XCTAssertFalse(gateway.hasCommandDeviceForTesting)
    }

    func testLateRemovalOfAnOldDeviceDoesNotClearTheDeviceFromANewerScan() {
        let gateway = ImageCaptureDeviceGateway()
        let first = LifecycleCameraDevice()
        let second = LifecycleCameraDevice()

        gateway.deviceBrowser(ICDeviceBrowser(), didAdd: first, moreComing: false)
        gateway.refreshDeviceSessionForTesting()
        gateway.deviceBrowser(ICDeviceBrowser(), didAdd: second, moreComing: false)
        XCTAssertTrue(gateway.isCommandDeviceForTesting(second))

        // A removal callback for the superseded device arrives after the new one is bound.
        gateway.deviceBrowser(ICDeviceBrowser(), didRemove: first, moreGoing: false)
        gateway.didRemove(first)

        XCTAssertTrue(
            gateway.isCommandDeviceForTesting(second),
            "A late removal for a superseded device must not clear the current device."
        )
    }

    func testDeleteWithoutADeviceFailsPromptlyRatherThanWaitingOnTheFramework() async {
        let gateway = ImageCaptureDeviceGateway()
        let token = DeviceFileToken(
            generation: UUID(),
            objectHandle: 7,
            fingerprint: DeviceFileFingerprint(
                name: "IMG_0007.HEIC",
                kind: "HEIC",
                size: 10,
                timestamp: nil
            )
        )

        let started = Date()
        let summary = try? await gateway.delete(
            [token],
            confirmed: true,
            timeout: .seconds(180)
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 5, "A delete with no device must not wait for the framework timeout.")
        XCTAssertEqual(summary?.successful.count, 0)
        XCTAssertEqual(summary?.failed.count, 1)
        XCTAssertNotNil(summary?.failed.first?.reason)
    }
}

@MainActor
private final class LifecycleCameraDevice: ICCameraDevice {
    override func requestOpenSession() {}
    override func requestCloseSession() {}
}
