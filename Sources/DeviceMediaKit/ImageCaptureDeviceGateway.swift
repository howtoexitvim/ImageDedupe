import CryptoKit
import DeduperCore
import Foundation
@preconcurrency import ImageCaptureCore

public enum DeviceGatewayError: Error, Equatable, LocalizedError, Sendable {
    case invalidBrowserMask
    case noDevice
    case staleToken
    case fileUnavailable
    case framework(String)
    case timeout(String)
    case canceled

    public var errorDescription: String? {
        switch self {
        case .invalidBrowserMask:
            return "ImageCaptureCore rejected the camera browser mask."
        case .noDevice:
            return "No unlocked iPhone is available."
        case .staleToken:
            return "This item belongs to an older device scan. Scan again and retry."
        case .fileUnavailable:
            return "The selected device item is no longer available."
        case .framework(let message):
            return message
        case .timeout(let operation):
            return "Timed out waiting for \(operation)."
        case .canceled:
            return "The device operation was canceled."
        }
    }
}

@MainActor
public final class ImageCaptureDeviceGateway: NSObject, @preconcurrency ICDeviceBrowserDelegate, @preconcurrency ICCameraDeviceDelegate {
    private let deviceNameContains: String?
    private let scheduler: DeviceCommandScheduler
    private let openSessionRetryDelay: Duration
    private let browser = ICDeviceBrowser()

    /// The device the browser is currently tracking. Cleared whenever browsing stops.
    private var selectedDevice: ICCameraDevice?

    /// The device later commands run against.
    ///
    /// ImageCaptureCore removes the browsed device when the browser stops, and the gateway
    /// deliberately stops browsing once a catalog arrives. Clearing the command device on
    /// that removal is what made a normal Delete report `No unlocked iPhone is available.`
    /// while Download still worked from its retained `ICCameraFile`. The successful session
    /// is therefore kept here and refreshed only when a new full scan runs.
    private var commandDevice: ICCameraDevice?

    /// True once the gateway has stopped the browser itself, so the removal callbacks that
    /// follow are expected bookkeeping rather than a physical disconnect.
    ///
    /// Deliberately not a short timing window: ImageCaptureCore may deliver the removal
    /// well after `stop()` returns, and a window that had already closed would clear the
    /// command device and reintroduce the very bug this fixes. The flag is instead reset
    /// when browsing next starts.
    private var hasStoppedBrowserDeliberately = false

    private var catalogGeneration: UUID?
    private var filesByToken: [DeviceFileToken: ICCameraFile] = [:]
    private var filenamesByToken: [DeviceFileToken: String] = [:]

    private var scanCallback: DeviceOneShotCallback<DeviceCatalogSnapshot>?
    private var scanCallbackToken: UUID?
    private var scanAbortError: DeviceCallbackError?
    private var openSessionRetryTask: Task<Void, Never>?
    private var activeFrameworkProgress: Progress?

    public init(
        deviceNameContains: String? = nil,
        scheduler: DeviceCommandScheduler = DeviceCommandScheduler(),
        openSessionRetryDelay: Duration = .seconds(1)
    ) {
        self.deviceNameContains = deviceNameContains
        self.scheduler = scheduler
        self.openSessionRetryDelay = openSessionRetryDelay
        super.init()
        browser.delegate = self
    }

    public func scan(timeout: Duration = .seconds(120)) async throws -> DeviceCatalogSnapshot {
        let lease = try await scheduler.acquire(priority: .high, generation: nil)
        defer { Task { await scheduler.release(lease) } }

        if let previousGeneration = catalogGeneration {
            await scheduler.cancelQueued(generation: previousGeneration)
        }
        // A new full scan is the one place the previous session is deliberately discarded.
        refreshDeviceSession()
        filesByToken.removeAll(keepingCapacity: true)
        filenamesByToken.removeAll(keepingCapacity: true)
        catalogGeneration = nil

        guard let deviceMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        ) else {
            throw DeviceGatewayError.invalidBrowserMask
        }

        let callback = DeviceOneShotCallback<DeviceCatalogSnapshot>()
        scanCallback = callback
        browser.browsedDeviceTypeMask = deviceMask

        do {
            let snapshot = try await callback.wait(
                timeout: timeout,
                onTimeout: {
                    await self.scheduler.invalidate()
                    self.abortScan(with: .timedOut)
                },
                onCancel: {
                    await self.scheduler.invalidate()
                    self.abortScan(with: .canceled)
                }
            ) { token in
                self.scanCallbackToken = token
                // Browsing is live again, so removals once more mean a real disconnect.
                self.hasStoppedBrowserDeliberately = false
                self.browser.start()
            }
            stopBrowsing()
            scanCallback = nil
            scanCallbackToken = nil
            return snapshot
        } catch let error as DeviceCallbackError {
            stopBrowsing()
            scanCallback = nil
            scanCallbackToken = nil
            switch error {
            case .timedOut:
                throw DeviceGatewayError.timeout("iPhone media catalog")
            case .canceled:
                throw DeviceGatewayError.canceled
            case .failed(let message):
                throw DeviceGatewayError.framework(message)
            }
        }
    }

    public func thumbnailData(
        for token: DeviceFileToken,
        maxPixelSize: Int? = nil,
        timeout: Duration = .seconds(20)
    ) async throws -> Data {
        let lease = try await scheduler.acquire(priority: .low, generation: token.generation)
        defer { Task { await scheduler.release(lease) } }
        let file = try resolveFile(for: token)
        let callback = DeviceOneShotCallback<Data>()
        let options: [ICCameraItemThumbnailOption: Any]
        if let maxPixelSize {
            options = [.imageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)]
        } else {
            options = [:]
        }

        do {
            return try await callback.wait(
                timeout: timeout,
                onTimeout: { await self.scheduler.invalidate() },
                onCancel: { await self.scheduler.invalidate() }
            ) { requestToken in
                file.requestThumbnailData(
                    options: options,
                    completion: DeviceFrameworkCallbackBridge.hop(
                        transform: { data, error in
                            (data, error?.localizedDescription)
                        },
                        deliver: { data, failure in
                            if let data, !data.isEmpty {
                                callback.complete(token: requestToken, result: .success(data))
                            } else {
                                callback.complete(
                                    token: requestToken,
                                    result: .failure(.failed(failure ?? "The device returned no thumbnail data."))
                                )
                            }
                        }
                    )
                )
            }
        } catch {
            throw mapCallbackError(error, operation: "thumbnail")
        }
    }

    public func metadata(
        for token: DeviceFileToken,
        timeout: Duration = .seconds(20)
    ) async throws -> MediaMetadataSummary? {
        let lease = try await scheduler.acquire(priority: .low, generation: token.generation)
        defer { Task { await scheduler.release(lease) } }
        let file = try resolveFile(for: token)
        let callback = DeviceOneShotCallback<MediaMetadataSummary?>()

        do {
            return try await callback.wait(
                timeout: timeout,
                onTimeout: { await self.scheduler.invalidate() },
                onCancel: { await self.scheduler.invalidate() }
            ) { requestToken in
                file.requestMetadataDictionary(
                    options: nil,
                    completion: DeviceFrameworkCallbackBridge.hop(
                        transform: { metadata, error in
                            (metadata.map(Self.makeMetadataSummary), error?.localizedDescription)
                        },
                        deliver: { summary, failure in
                            if let failure {
                                callback.complete(token: requestToken, result: .failure(.failed(failure)))
                            } else {
                                callback.complete(token: requestToken, result: .success(summary))
                            }
                        }
                    )
                )
            }
        } catch {
            throw mapCallbackError(error, operation: "metadata")
        }
    }

    public func download(
        _ tokens: [DeviceFileToken],
        to stagingSession: ImportStagingSession,
        cancellation: DeviceOperationCancellation? = nil,
        onProgress: ((DeviceBatchProgress) -> Void)? = nil,
        timeout: Duration = .seconds(120)
    ) async -> DeviceGatewayImportSummary {
        var summary = DeviceGatewayImportSummary()
        let total = tokens.count
        onProgress?(DeviceBatchProgress(
            completedItems: 0,
            totalItems: total,
            currentFilename: nil,
            fractionCompleted: total == 0 ? 1 : 0
        ))

        downloadLoop: for (index, token) in tokens.enumerated() {
            if cancellation?.isCancellationRequested == true {
                summary.canceled.append(contentsOf: tokens[index...])
                break
            }
            let filename = filenamesByToken[token] ?? token.fingerprint.name
            onProgress?(DeviceBatchProgress(
                completedItems: index,
                totalItems: total,
                currentFilename: filename,
                fractionCompleted: Double(index) / Double(max(1, total))
            ))

            do {
                let downloaded = try await downloadOne(
                    token,
                    to: stagingSession,
                    cancellation: cancellation,
                    timeout: timeout
                )
                summary.successful.append(downloaded)
            } catch DeviceGatewayError.canceled {
                summary.canceled.append(contentsOf: tokens[index...])
                break
            } catch let error as DeviceGatewayError {
                summary.failed.append(DeviceOperationFailure(
                    token: token,
                    filename: filename,
                    reason: error.localizedDescription
                ))
                if case .timeout = error {
                    for unsubmitted in tokens.dropFirst(index + 1) {
                        summary.failed.append(DeviceOperationFailure(
                            token: unsubmitted,
                            filename: filenamesByToken[unsubmitted] ?? unsubmitted.fingerprint.name,
                            reason: "Not submitted because the previous download timed out and the device gateway was stopped."
                        ))
                    }
                    break downloadLoop
                }
            } catch {
                summary.failed.append(DeviceOperationFailure(
                    token: token,
                    filename: filename,
                    reason: error.localizedDescription
                ))
            }

            onProgress?(DeviceBatchProgress(
                completedItems: index + 1,
                totalItems: total,
                currentFilename: filename,
                fractionCompleted: Double(index + 1) / Double(max(1, total))
            ))
        }
        return summary
    }

    public func delete(
        _ tokens: [DeviceFileToken],
        confirmed: Bool,
        cancellation: DeviceOperationCancellation? = nil,
        onProgress: ((DeviceBatchProgress) -> Void)? = nil,
        timeout: Duration = .seconds(120)
    ) async throws -> DeviceGatewayDeleteSummary {
        guard confirmed else {
            throw DeviceMediaError.deleteNotConfirmed
        }
        let lease = try await scheduler.acquire(priority: .high, generation: tokens.first?.generation)
        defer { Task { await scheduler.release(lease) } }
        var summary = DeviceGatewayDeleteSummary()

        // Fail the whole batch up front when nothing can be submitted, rather than letting
        // each item wait on the framework. Nothing reached the device, so the caller can
        // report an honest, immediate failure instead of a long destructive-looking phase.
        guard commandDevice != nil else {
            summary.failed = tokens.map { token in
                DeviceOperationFailure(
                    token: token,
                    filename: filenamesByToken[token] ?? token.fingerprint.name,
                    reason: DeviceGatewayError.noDevice.localizedDescription
                )
            }
            return summary
        }

        let total = tokens.count
        onProgress?(DeviceBatchProgress(
            completedItems: 0,
            totalItems: total,
            currentFilename: nil,
            fractionCompleted: total == 0 ? 1 : 0
        ))

        deleteLoop: for (index, token) in tokens.enumerated() {
            if cancellation?.isCancellationRequested == true {
                summary.canceled.append(contentsOf: tokens[index...])
                break
            }
            let filename = filenamesByToken[token] ?? token.fingerprint.name
            onProgress?(DeviceBatchProgress(
                completedItems: index,
                totalItems: total,
                currentFilename: filename,
                fractionCompleted: Double(index) / Double(max(1, total))
            ))
            do {
                try await deleteOne(token, cancellation: cancellation, timeout: timeout)
                summary.successful.append(token)
            } catch DeviceGatewayError.canceled {
                summary.canceled.append(contentsOf: tokens[index...])
                break
            } catch let error as DeviceGatewayError {
                summary.failed.append(DeviceOperationFailure(
                    token: token,
                    filename: filename,
                    reason: error.localizedDescription
                ))
                if case .timeout = error {
                    for unsubmitted in tokens.dropFirst(index + 1) {
                        summary.failed.append(DeviceOperationFailure(
                            token: unsubmitted,
                            filename: filenamesByToken[unsubmitted] ?? unsubmitted.fingerprint.name,
                            reason: "Not submitted because the previous delete timed out and the device gateway was stopped."
                        ))
                    }
                    break deleteLoop
                }
            } catch {
                summary.failed.append(DeviceOperationFailure(
                    token: token,
                    filename: filename,
                    reason: error.localizedDescription
                ))
            }
            onProgress?(DeviceBatchProgress(
                completedItems: index + 1,
                totalItems: total,
                currentFilename: filename,
                fractionCompleted: Double(index + 1) / Double(max(1, total))
            ))
        }
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
        commandDevice = camera
        camera.delegate = self
        requestOpenSession(on: camera)
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        handleRemoval(of: device)
    }

    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let scanAbortError {
            if error == nil, device.hasOpenSession {
                device.requestCloseSession()
            } else {
                self.scanAbortError = nil
                finishScan(.failure(scanAbortError))
            }
            return
        }
        if let error {
            let frameworkError = error as NSError
            if OpenSessionRetry.shouldRetry(
                domain: frameworkError.domain,
                code: frameworkError.code,
                description: frameworkError.localizedDescription
            ) {
                scheduleOpenSessionRetry(for: device)
                return
            }
            finishScan(.failure(.failed("Could not open ImageCaptureCore session: \(error.localizedDescription)")))
        } else {
            cancelOpenSessionRetry()
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        // `abortScan` stops browsing before requesting the close, so the aborting device is
        // no longer the browsed one by the time this lands. Matching only `selectedDevice`
        // here would leave the abort waiting for a callback that can never match.
        guard scanAbortError != nil else { return }
        let abortError = scanAbortError
        scanAbortError = nil
        if let abortError {
            finishScan(.failure(abortError))
        }
    }

    public func didRemove(_ device: ICDevice) {
        handleRemoval(of: device)
    }

    /// Distinguishes the removal that follows a deliberate browser stop from a real
    /// disconnect, and ignores late removals for a device a newer scan has superseded.
    private func handleRemoval(of device: ICDevice) {
        let wasBrowsedDevice = selectedDevice === device
        if wasBrowsedDevice {
            selectedDevice = nil
        }

        guard commandDevice === device else {
            // A late callback for a superseded device must not disturb the current session.
            return
        }

        if hasStoppedBrowserDeliberately {
            // ImageCaptureCore always removes the browsed device when the browser stops.
            // The session stays usable for a later Delete.
            return
        }

        commandDevice = nil
        if wasBrowsedDevice {
            finishScan(.failure(.failed("The iPhone was disconnected while scanning.")))
        }
    }

    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        guard device === selectedDevice else { return }
        let generation = UUID()
        let cameraFiles = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        var resolved: [DeviceFileToken: ICCameraFile] = [:]
        var catalogIndex = DeviceCatalogIndex()
        for (index, file) in cameraFiles.enumerated() {
            let model = Self.makeDeviceMediaFile(file, fallbackIndex: index)
            let token = DeviceFileToken(
                generation: generation,
                objectHandle: file.ptpObjectHandle,
                fingerprint: DeviceFileFingerprint(
                    name: model.name,
                    kind: model.kind,
                    size: model.size,
                    timestamp: Self.timestampDate(for: file)
                )
            )
            let catalogFile = DeviceCatalogFile(model: model, token: token)
            guard catalogIndex.insert(catalogFile) else { continue }
            resolved[token] = file
        }
        catalogGeneration = generation
        filesByToken = resolved
        filenamesByToken = catalogIndex.filenamesByToken
        finishScan(.success(DeviceCatalogSnapshot(
            generation: generation,
            deviceName: device.name ?? "unknown",
            deviceIdentityHash: Self.deviceIdentityHash(for: device),
            files: catalogIndex.files
        )))
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

    private func resolveFile(for token: DeviceFileToken) throws -> ICCameraFile {
        guard token.generation == catalogGeneration else {
            throw DeviceGatewayError.staleToken
        }
        guard let file = filesByToken[token] else {
            throw DeviceGatewayError.fileUnavailable
        }
        return file
    }

    private func downloadOne(
        _ token: DeviceFileToken,
        to stagingSession: ImportStagingSession,
        cancellation: DeviceOperationCancellation?,
        timeout: Duration
    ) async throws -> DeviceDownloadSuccess {
        let lease = try await scheduler.acquire(priority: .high, generation: token.generation)
        defer { Task { await scheduler.release(lease) } }
        let file = try resolveFile(for: token)
        let callback = DeviceOneShotCallback<String>()
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: stagingSession.directory as NSURL,
            .overwrite: false
        ]
        defer {
            cancellation?.unbind(activeFrameworkProgress)
            activeFrameworkProgress = nil
        }

        do {
            let filename = try await callback.wait(
                timeout: timeout,
                onTimeout: {
                    await self.scheduler.invalidate()
                    self.cancelActiveProgress()
                },
                onCancel: {
                    await self.scheduler.invalidate()
                    self.cancelActiveProgress()
                }
            ) { requestToken in
                let progress = file.requestDownload(
                    options: options,
                    completion: DeviceFrameworkCallbackBridge.hop(
                        transform: { filename, error in
                            (filename, error?.localizedDescription)
                        },
                        deliver: { safeFilename, failure in
                            if cancellation?.isCancellationRequested == true {
                                callback.complete(token: requestToken, result: .failure(.canceled))
                            } else if let failure {
                                callback.complete(token: requestToken, result: .failure(.failed(failure)))
                            } else if let safeFilename {
                                callback.complete(token: requestToken, result: .success(safeFilename))
                            } else {
                                callback.complete(
                                    token: requestToken,
                                    result: .failure(.failed("The device returned no download filename."))
                                )
                            }
                        }
                    )
                )
                self.activeFrameworkProgress = progress
                cancellation?.bind(progress) {
                    Task { @MainActor in
                        await self.scheduler.invalidate()
                        callback.complete(token: requestToken, result: .failure(.canceled))
                    }
                }
            }
            let stagedFile = try ImportedFilePathPolicy.validateCompletedDownload(
                callbackFilename: filename,
                destination: stagingSession.directory
            )
            let stagedIdentity = try StagedFileIdentity.capture(
                filename: stagedFile.lastPathComponent,
                stagingDirectory: stagingSession.directory,
                stagingIdentity: stagingSession.identity
            )
            return DeviceDownloadSuccess(
                token: token,
                filename: stagedFile.lastPathComponent,
                stagedIdentity: stagedIdentity
            )
        } catch {
            throw mapCallbackError(error, operation: "download")
        }
    }

    private func deleteOne(
        _ token: DeviceFileToken,
        cancellation: DeviceOperationCancellation?,
        timeout: Duration
    ) async throws {
        guard let device = commandDevice else {
            throw DeviceGatewayError.noDevice
        }
        let file = try resolveFile(for: token)
        let callback = DeviceOneShotCallback<Bool>()
        defer {
            cancellation?.unbind(activeFrameworkProgress)
            activeFrameworkProgress = nil
        }

        do {
            _ = try await callback.wait(
                timeout: timeout,
                onTimeout: {
                    await self.scheduler.invalidate()
                    self.cancelActiveProgress()
                    device.cancelDelete()
                },
                onCancel: {
                    await self.scheduler.invalidate()
                    self.cancelActiveProgress()
                    device.cancelDelete()
                }
            ) { requestToken in
                let progress = device.requestDeleteFiles(
                    [file],
                    deleteFailed: DeviceFrameworkCallbackBridge.ignore(),
                    completion: DeviceFrameworkCallbackBridge.hop(
                        transform: { result, error in
                            ((result[.successful] ?? []).isEmpty == false, error?.localizedDescription)
                        },
                        deliver: { successful, failure in
                            if cancellation?.isCancellationRequested == true {
                                callback.complete(token: requestToken, result: .failure(.canceled))
                            } else if successful {
                                callback.complete(token: requestToken, result: .success(true))
                            } else {
                                callback.complete(
                                    token: requestToken,
                                    result: .failure(.failed(failure ?? "The device did not confirm deletion."))
                                )
                            }
                        }
                    )
                )
                self.activeFrameworkProgress = progress
                cancellation?.bind(progress) {
                    progress?.cancel()
                    device.cancelDelete()
                    Task { @MainActor in
                        await self.scheduler.invalidate()
                        callback.complete(token: requestToken, result: .failure(.canceled))
                    }
                }
            }
        } catch {
            throw mapCallbackError(error, operation: "delete")
        }
    }

    private func finishScan(_ result: Result<DeviceCatalogSnapshot, DeviceCallbackError>) {
        guard let callback = scanCallback, let token = scanCallbackToken else { return }
        cancelOpenSessionRetry()
        scanAbortError = nil
        callback.complete(token: token, result: result)
    }

    private func abortScan(with error: DeviceCallbackError) {
        cancelOpenSessionRetry()
        // Read the device before stopping: `stopBrowsing` clears the browsed binding. An
        // aborted scan produced no trustworthy catalog, so its session is discarded too.
        let abortingDevice = selectedDevice ?? commandDevice
        stopBrowsing()
        commandDevice = nil
        guard let abortingDevice else {
            finishScan(.failure(error))
            return
        }
        scanAbortError = error
        if abortingDevice.hasOpenSession {
            abortingDevice.requestCloseSession()
        }
    }

    private func cancelActiveProgress() {
        activeFrameworkProgress?.cancel()
    }

    /// Stops browsing without discarding the command session.
    ///
    /// The removal callbacks ImageCaptureCore delivers during and just after `stop()` are
    /// flagged as deliberate so they cannot clear `commandDevice`. The flag is cleared on
    /// the next main-actor turn, after the framework has drained those callbacks, so a real
    /// disconnect arriving later is still handled as a disconnect.
    private func stopBrowsing() {
        hasStoppedBrowserDeliberately = true
        browser.stop()
        selectedDevice = nil
    }

    /// Discards the retained session so a new full scan starts from a clean device binding.
    private func refreshDeviceSession() {
        stopBrowsing()
        commandDevice = nil
    }

    // MARK: - Test seams
    //
    // The device-session lifecycle is only observable through ImageCaptureCore callbacks,
    // so these expose the binding without reaching into the framework.

    /// Whether a device is available for a later Download or Delete.
    public var hasCommandDeviceForTesting: Bool { commandDevice != nil }

    public func isCommandDeviceForTesting(_ device: ICDevice) -> Bool {
        commandDevice === device
    }

    public func stopBrowsingForTesting() {
        stopBrowsing()
    }

    public func refreshDeviceSessionForTesting() {
        refreshDeviceSession()
    }

    private func mapCallbackError(_ error: Error, operation: String) -> DeviceGatewayError {
        guard let callbackError = error as? DeviceCallbackError else {
            return .framework(error.localizedDescription)
        }
        switch callbackError {
        case .timedOut:
            return .timeout(operation)
        case .canceled:
            return .canceled
        case .failed(let message):
            return .framework(message)
        }
    }

    nonisolated private static func makeMetadataSummary(_ metadata: [AnyHashable: Any]) -> MediaMetadataSummary {
        let values = Dictionary(uniqueKeysWithValues: metadata.map { (String(describing: $0.key), $0.value) })
        let gps = values["{GPS}"] as? [String: Any] ?? values["GPS"] as? [String: Any] ?? [:]
        let exif = values["{Exif}"] as? [String: Any] ?? values["Exif"] as? [String: Any] ?? [:]
        let tiff = values["{TIFF}"] as? [String: Any] ?? values["TIFF"] as? [String: Any] ?? [:]
        return MediaMetadataSummary(
            location: MediaMetadataSummary.locationText(fromGPS: gps),
            aperture: MediaMetadataSummary.apertureText(fromExif: exif),
            colorSpace: MediaMetadataSummary.colorSpaceText(from: values, exif: exif),
            shutterSpeed: MediaMetadataSummary.shutterText(fromExif: exif),
            maker: tiff["Make"] as? String,
            model: tiff["Model"] as? String
        )
    }

    private static func deviceIdentityHash(for device: ICDevice) -> String? {
        guard let identifier = device.persistentIDString ?? device.uuidString ?? device.serialNumberString,
              !identifier.isEmpty else {
            return nil
        }
        return SHA256.hash(data: Data(identifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func makeDeviceMediaFile(_ file: ICCameraFile, fallbackIndex: Int) -> DeviceMediaFile {
        let name = file.name ?? file.originalFilename ?? "unknown-\(fallbackIndex)"
        return DeviceMediaFile(
            id: "\(file.ptpObjectHandle)-\(fallbackIndex)-\(name)",
            name: name,
            kind: kind(for: file, name: name),
            size: Int64(file.fileSize),
            timestamp: timestampDate(for: file).map { timestampFormatter.string(from: $0) },
            width: file.width > 0 ? file.width : nil,
            height: file.height > 0 ? file.height : nil,
            duration: file.duration > 0 ? file.duration : nil,
            location: file.gpsString,
            groupUUID: file.groupUUID,
            burstUUID: file.burstUUID,
            isRaw: file.isRaw,
            isHighFramerate: file.highFramerate,
            isTimeLapse: file.timeLapse
        )
    }

    private static func kind(for file: ICCameraFile, name: String) -> String {
        if let ext = name.split(separator: ".").last, ext != name {
            return ext.uppercased()
        }
        return file.uti?.uppercased() ?? "UNKNOWN"
    }

    private static func timestampDate(for file: ICCameraFile) -> Date? {
        file.exifCreationDate
            ?? file.fileCreationDate
            ?? file.creationDate
            ?? file.fileModificationDate
            ?? file.modificationDate
    }

    private static var timestampFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private func scheduleOpenSessionRetry(for device: ICDevice) {
        guard let camera = device as? ICCameraDevice, selectedDevice === camera else { return }
        cancelOpenSessionRetry()
        let expectedDevice = ObjectIdentifier(camera)
        openSessionRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.openSessionRetryDelay)
            } catch {
                return
            }
            guard
                !Task.isCancelled,
                self.scanAbortError == nil,
                let selectedDevice = self.selectedDevice,
                ObjectIdentifier(selectedDevice) == expectedDevice
            else {
                return
            }
            self.openSessionRetryTask = nil
            self.requestOpenSession(on: selectedDevice)
        }
    }

    private func requestOpenSession(on device: ICDevice) {
        device.requestOpenSession()
    }

    private func cancelOpenSessionRetry() {
        openSessionRetryTask?.cancel()
        openSessionRetryTask = nil
    }
}
