import AppKit
import ImageCaptureCore
import ImageIO

public enum ThumbnailProvider {
    public static func thumbnail(for file: ICCameraFile, timeoutSeconds: TimeInterval = 20) -> NSImage? {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ThumbnailResult()

        file.requestThumbnailData(options: [:]) { data, _ in
            result.data = data
            semaphore.signal()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if semaphore.wait(timeout: .now() + 0.05) == .success {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        guard let data = result.data, !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private final class ThumbnailResult: @unchecked Sendable {
    private let lock = NSLock()
    private var _data: Data?

    var data: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _data
        }
        set {
            lock.lock()
            _data = newValue
            lock.unlock()
        }
    }
}
