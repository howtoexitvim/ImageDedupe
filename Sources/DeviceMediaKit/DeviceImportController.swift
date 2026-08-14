import Foundation
import ImageCaptureCore

public final class DeviceImportController {
    private let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 120) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func importFiles(_ files: [ICCameraFile], to destination: URL) -> DeviceImportSummary {
        var summary = DeviceImportSummary(successful: [], failed: [])

        for file in files {
            let result = DownloadResult()
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: destination as NSURL
            ]
            _ = file.requestDownload(options: options) { filename, error in
                result.filename = filename
                result.error = error
                result.isDone = true
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while !result.isDone && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }

            if let error = result.error {
                summary.failed.append((file: file, error: error))
            } else if let filename = result.filename {
                summary.successful.append((file: file, filename: filename))
            } else {
                summary.failed.append((file: file, error: DeviceMediaError.timeout("Timed out importing \(file.name ?? "file").")))
            }
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
