import Foundation
import ImageCaptureCore
import DeduperCore

public enum MetadataProvider {
    public static func metadata(for file: ICCameraFile, timeoutSeconds: TimeInterval = 20) -> [AnyHashable: Any]? {
        let semaphore = DispatchSemaphore(value: 0)
        let result = MetadataResult()

        file.requestMetadataDictionary(options: nil) { metadata, _ in
            result.metadata = metadata
            semaphore.signal()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if semaphore.wait(timeout: .now() + 0.05) == .success {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return result.metadata
    }

    public static func summary(for file: ICCameraFile, timeoutSeconds: TimeInterval = 20) -> MediaMetadataSummary? {
        guard let metadata = metadata(for: file, timeoutSeconds: timeoutSeconds) else {
            return nil
        }
        let stringMetadata = Dictionary(uniqueKeysWithValues: metadata.map { (String(describing: $0.key), $0.value) })
        let gps = stringMetadata["{GPS}"] as? [String: Any] ?? stringMetadata["GPS"] as? [String: Any] ?? [:]
        let exif = stringMetadata["{Exif}"] as? [String: Any] ?? stringMetadata["Exif"] as? [String: Any] ?? [:]
        let tiff = stringMetadata["{TIFF}"] as? [String: Any] ?? stringMetadata["TIFF"] as? [String: Any] ?? [:]

        return MediaMetadataSummary(
            location: MediaMetadataSummary.locationText(fromGPS: gps),
            aperture: MediaMetadataSummary.apertureText(fromExif: exif),
            colorSpace: MediaMetadataSummary.colorSpaceText(from: stringMetadata, exif: exif),
            shutterSpeed: MediaMetadataSummary.shutterText(fromExif: exif),
            maker: tiff["Make"] as? String,
            model: tiff["Model"] as? String
        )
    }
}

private final class MetadataResult: @unchecked Sendable {
    private let lock = NSLock()
    private var _metadata: [AnyHashable: Any]?

    var metadata: [AnyHashable: Any]? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _metadata
        }
        set {
            lock.lock()
            _metadata = newValue
            lock.unlock()
        }
    }
}
