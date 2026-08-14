import ImageCaptureCore

public struct DeviceImportSummary {
    public var successful: [(file: ICCameraFile, filename: String)]
    public var failed: [(file: ICCameraFile, error: Error)]

    public init(successful: [(file: ICCameraFile, filename: String)], failed: [(file: ICCameraFile, error: Error)]) {
        self.successful = successful
        self.failed = failed
    }
}
