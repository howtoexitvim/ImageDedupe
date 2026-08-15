import AppKit
import ImageCaptureCore
import ImageIO

public enum InspectorPreviewProvider {
    public static let maximumPixelSize = 2_048

    public static func requestedMaxPixelSize(width: Int?, height: Int?) -> Int {
        let knownLongestEdge = max(width ?? 0, height ?? 0)
        guard knownLongestEdge > 0 else { return maximumPixelSize }
        return min(knownLongestEdge, maximumPixelSize)
    }

    public static func requestPreview(
        for file: ICCameraFile,
        maxPixelSize: Int,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) {
        let clampedSize = max(1, min(maxPixelSize, maximumPixelSize))
        file.requestThumbnailData(
            options: [.imageSourceThumbnailMaxPixelSize: clampedSize]
        ) { data, _ in
            completion(data.flatMap { decode($0, maxPixelSize: clampedSize) })
        }
    }

    static func decode(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return nil
        }

        let target = max(1, min(max(width, height), maxPixelSize, maximumPixelSize))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        let representation = NSBitmapImageRep(cgImage: image)
        let result = NSImage(size: NSSize(width: image.width, height: image.height))
        result.addRepresentation(representation)
        return result
    }
}
