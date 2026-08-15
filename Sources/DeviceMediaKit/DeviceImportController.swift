import Foundation
import ImageCaptureCore

public final class DeviceImportController {
    private let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 120) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func importFiles(
        _ files: [ICCameraFile],
        to destination: URL,
        cancellation: DeviceOperationCancellation? = nil,
        onProgress: (@Sendable (DeviceBatchProgress) -> Void)? = nil
    ) -> DeviceImportSummary {
        var summary = DeviceImportSummary(successful: [], failed: [], canceled: [])
        let total = files.count

        guard total > 0 else {
            onProgress?(DeviceBatchProgress(
                completedItems: 0,
                totalItems: 0,
                currentFilename: nil,
                fractionCompleted: 1
            ))
            return summary
        }

        for (index, file) in files.enumerated() {
            if cancellation?.isCancellationRequested == true {
                summary.canceled.append(contentsOf: files[index...])
                break
            }

            let filename = file.name ?? "file"
            onProgress?(DeviceBatchProgress(
                completedItems: index,
                totalItems: total,
                currentFilename: filename,
                fractionCompleted: Double(index) / Double(total)
            ))

            let result = DownloadResult()
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: destination as NSURL
            ]
            let systemProgress = file.requestDownload(options: options) { downloadedFilename, error in
                result.filename = downloadedFilename
                result.error = error
                result.isDone = true
            }
            cancellation?.bind(systemProgress)

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while !result.isDone && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                let itemFraction = systemProgress?.fractionCompleted ?? 0
                onProgress?(DeviceBatchProgress(
                    completedItems: index,
                    totalItems: total,
                    currentFilename: filename,
                    fractionCompleted: (Double(index) + itemFraction) / Double(total)
                ))

                if cancellation?.isCancellationRequested == true {
                    systemProgress?.cancel()
                    break
                }
            }
            cancellation?.unbind(systemProgress)

            if cancellation?.isCancellationRequested == true, !result.isDone {
                summary.canceled.append(contentsOf: files[index...])
                break
            }

            if let error = result.error {
                summary.failed.append((file: file, error: error))
            } else if let filename = result.filename {
                summary.successful.append((file: file, filename: filename))
            } else {
                summary.failed.append((file: file, error: DeviceMediaError.timeout("Timed out importing \(filename).")))
            }

            onProgress?(DeviceBatchProgress(
                completedItems: index + 1,
                totalItems: total,
                currentFilename: filename,
                fractionCompleted: Double(index + 1) / Double(total)
            ))
        }

        return summary
    }
}

private final class DownloadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var _isDone = false
    private var _filename: String?
    private var _error: Error?

    var isDone: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isDone
        }
        set {
            lock.lock()
            _isDone = newValue
            lock.unlock()
        }
    }

    var filename: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _filename
        }
        set {
            lock.lock()
            _filename = newValue
            lock.unlock()
        }
    }

    var error: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _error
        }
        set {
            lock.lock()
            _error = newValue
            lock.unlock()
        }
    }
}
