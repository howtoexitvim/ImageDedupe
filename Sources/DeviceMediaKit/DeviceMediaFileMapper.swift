import DeduperCore
import Foundation
import ImageCaptureCore

public enum DeviceMediaFileMapper {
    public static func makeDeviceMediaFile(_ file: ICCameraFile, fallbackIndex: Int) -> DeviceMediaFile {
        let name = file.name ?? file.originalFilename ?? "unknown-\(fallbackIndex)"
        return DeviceMediaFile(
            id: "\(file.ptpObjectHandle)-\(fallbackIndex)-\(name)",
            name: name,
            kind: kind(for: file, name: name),
            size: Int64(file.fileSize),
            timestamp: timestamp(for: file),
            width: file.width > 0 ? file.width : nil,
            height: file.height > 0 ? file.height : nil
        )
    }

    private static func kind(for file: ICCameraFile, name: String) -> String {
        if let ext = name.split(separator: ".").last, ext != name {
            return ext.uppercased()
        }
        return file.uti?.uppercased() ?? "UNKNOWN"
    }

    private static func timestamp(for file: ICCameraFile) -> String? {
        let date = file.exifCreationDate ?? file.fileCreationDate ?? file.creationDate ?? file.fileModificationDate ?? file.modificationDate
        guard let date else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
