import DeduperCore
@preconcurrency import ImageCaptureCore
import XCTest
@testable import DeviceMediaKit

/// Fast delete verification without a full rescan.
///
/// Phase 8 verified every delete by rescanning the whole catalog (~4,000 files), which is
/// why a one-photo delete felt far slower than the Phase 6 flow that simply trusted the
/// framework callback. Trusting the callback is not an option — a device test showed a
/// callback-reported success (`IMG_3879.HEIC`) that was still present on the phone.
///
/// ImageCaptureCore already reports removals on the open session via
/// `cameraDevice(_:didRemove:)`. That is authoritative and free, so it can confirm the
/// common case immediately, leaving the full rescan as the fallback.
@MainActor
final class DeviceRemovalObservationTests: XCTestCase {
    func testFrameworkRemovalCallbackConfirmsDeletionWithoutARescan() {
        let gateway = ImageCaptureDeviceGateway()
        let handle: UInt32 = 4242

        gateway.recordObservedRemovalsForTesting([handle])

        XCTAssertTrue(gateway.hasObservedRemoval(objectHandle: handle))
    }

    func testUnrelatedRemovalDoesNotConfirmADifferentFile() {
        let gateway = ImageCaptureDeviceGateway()

        gateway.recordObservedRemovalsForTesting([1])

        XCTAssertFalse(gateway.hasObservedRemoval(objectHandle: 2))
    }

    func testObservedRemovalsResetOnANewScanSoStaleEvidenceCannotConfirm() {
        let gateway = ImageCaptureDeviceGateway()
        gateway.recordObservedRemovalsForTesting([7])
        XCTAssertTrue(gateway.hasObservedRemoval(objectHandle: 7))

        // A new catalog means a new generation; handles may be reused for other files.
        gateway.refreshDeviceSessionForTesting()

        XCTAssertFalse(
            gateway.hasObservedRemoval(objectHandle: 7),
            "Removal evidence from an older session must not confirm a newer delete."
        )
    }

    func testRemovalDelegateCallbackRecordsTheHandle() {
        let gateway = ImageCaptureDeviceGateway()
        let camera = RemovalReportingCameraDevice()
        gateway.deviceBrowser(ICDeviceBrowser(), didAdd: camera, moreComing: false)

        let item = RemovalReportingCameraFile(handle: 99)
        gateway.cameraDevice(camera, didRemove: [item])

        XCTAssertTrue(gateway.hasObservedRemoval(objectHandle: 99))
    }
}

@MainActor
private final class RemovalReportingCameraDevice: ICCameraDevice {
    override func requestOpenSession() {}
    override func requestCloseSession() {}
}

@MainActor
private final class RemovalReportingCameraFile: ICCameraFile {
    private let handle: UInt32

    init(handle: UInt32) {
        self.handle = handle
        super.init()
    }

    override var ptpObjectHandle: UInt32 { handle }
}
