import DeduperCore
import Foundation
import ImageCaptureCore

public final class DeviceSessionController: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let deviceNameContains: String?
    private let timeoutSeconds: TimeInterval
    private let browser = ICDeviceBrowser()
    private var selectedDevice: ICCameraDevice?
    private var openError: Error?
    private var isReady = false
    private var removed = false

    public init(deviceNameContains: String? = nil, timeoutSeconds: TimeInterval = 120) {
        self.deviceNameContains = deviceNameContains
        self.timeoutSeconds = timeoutSeconds
        super.init()
        browser.delegate = self
    }

    public func scan() throws -> DeviceScanResult {
        guard let deviceMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue) else {
            throw DeviceMediaError.invalidDeviceBrowserMask
        }
        browser.browsedDeviceTypeMask = deviceMask
        browser.start()
        defer { browser.stop() }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while selectedDevice == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        guard let device = selectedDevice else {
            throw DeviceMediaError.noDevice
        }

        if device.isLocked || device.isAccessRestrictedAppleDevice {
            fputs("warning: ImageCaptureCore reports the device as locked/access-restricted; attempting session open anyway.\n", stderr)
        }

        device.delegate = self
        requestOpenSession(on: device)
        while !isReady && !removed && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))

            if let error = openError {
                if shouldRetryOpenSession(error) {
                    fputs("warning: iPhone still reports locked/access-restricted. Unlock it, keep the screen awake, and approve Trust This Mac if prompted; retrying until timeout.\n", stderr)
                    openError = nil
                    Thread.sleep(forTimeInterval: 1.0)
                    requestOpenSession(on: device)
                    continue
                }
                break
            }
        }

        if let openError {
            throw DeviceMediaError.openFailed("Could not open ImageCaptureCore session: \(openError)")
        }
        if removed {
            throw DeviceMediaError.noDevice
        }
        guard isReady else {
            throw DeviceMediaError.timeout("Timed out waiting for iPhone media catalog.")
        }

        let cameraFiles = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        let mapped = cameraFiles.enumerated().map { index, file in
            (DeviceMediaFileMapper.makeDeviceMediaFile(file, fallbackIndex: index), file)
        }
        return DeviceScanResult(deviceName: device.name ?? "unknown", device: device, files: mapped)
    }

    public func delete(
        _ files: [ICCameraFile],
        from device: ICCameraDevice,
        confirmed: Bool,
        cancellation: DeviceOperationCancellation? = nil,
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil
    ) throws -> DeviceDeleteSummary {
        guard confirmed else {
            throw DeviceMediaError.deleteNotConfirmed
        }
        guard cancellation?.isCancellationRequested != true else {
            return DeviceDeleteSummary(successful: [], failed: [], canceled: files, error: nil)
        }
        let total = files.count
        onProgress?(DeviceBatchProgress(
            completedItems: 0,
            totalItems: total,
            currentFilename: nil,
            fractionCompleted: total == 0 ? 1 : 0
        ))
        guard #available(macOS 10.15, *) else {
            device.requestDeleteFiles(files)
            onProgress?(DeviceBatchProgress(
                completedItems: total,
                totalItems: total,
                currentFilename: nil,
                fractionCompleted: 1
            ))
            return DeviceDeleteSummary(successful: files, failed: [], canceled: [], error: nil)
        }

        var done = false
        var summary = DeviceDeleteSummary(successful: [], failed: [], canceled: [], error: nil)
        let systemProgress = device.requestDeleteFiles(files, deleteFailed: { failures in
            summary.failed.append(contentsOf: failures.values.compactMap { $0 as? ICCameraFile })
        }, completion: { result, error in
            let successful = result[.successful] ?? []
            let failed = result[.failed] ?? []
            let canceled = result[.canceled] ?? []
            summary.successful = successful.compactMap { $0 as? ICCameraFile }
            summary.failed.append(contentsOf: failed.compactMap { $0 as? ICCameraFile })
            summary.canceled = canceled.compactMap { $0 as? ICCameraFile }
            summary.error = error
            done = true
        })
        cancellation?.bind(systemProgress)
        defer { cancellation?.unbind(systemProgress) }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var didForwardCancellation = false
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            let fraction = systemProgress?.fractionCompleted ?? 0
            onProgress?(DeviceBatchProgress(
                completedItems: Int((fraction * Double(total)).rounded(.down)),
                totalItems: total,
                currentFilename: nil,
                fractionCompleted: fraction
            ))

            if cancellation?.isCancellationRequested == true, !didForwardCancellation {
                didForwardCancellation = true
                systemProgress?.cancel()
                device.cancelDelete()
            }
        }

        guard done else {
            if cancellation?.isCancellationRequested == true {
                return DeviceDeleteSummary(successful: [], failed: [], canceled: files, error: nil)
            }
            throw DeviceMediaError.timeout("Timed out waiting for delete completion.")
        }
        onProgress?(DeviceBatchProgress(
            completedItems: total,
            totalItems: total,
            currentFilename: nil,
            fractionCompleted: 1
        ))
        return summary
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard selectedDevice == nil, let camera = device as? ICCameraDevice else {
            return
        }
        if let needle = deviceNameContains?.lowercased(),
           !(camera.name ?? "").lowercased().contains(needle) {
            return
        }
        selectedDevice = camera
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if selectedDevice === device {
            removed = true
        }
    }

    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        openError = error
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    public func didRemove(_ device: ICDevice) {
        if selectedDevice === device {
            removed = true
        }
    }

    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        isReady = true
    }

    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    private func requestOpenSession(on device: ICCameraDevice) {
        openError = nil
        device.requestOpenSession()
    }

    private func shouldRetryOpenSession(_ error: Error) -> Bool {
        let nsError = error as NSError
        return OpenSessionRetry.shouldRetry(
            domain: nsError.domain,
            code: nsError.code,
            description: nsError.localizedDescription
        )
    }
}
