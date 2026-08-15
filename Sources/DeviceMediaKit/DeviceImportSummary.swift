import ImageCaptureCore

public struct DeviceImportSummary {
    public var successful: [(file: ICCameraFile, filename: String)]
    public var failed: [(file: ICCameraFile, error: Error)]
    public var canceled: [ICCameraFile]

    public init(
        successful: [(file: ICCameraFile, filename: String)],
        failed: [(file: ICCameraFile, error: Error)],
        canceled: [ICCameraFile] = []
    ) {
        self.successful = successful
        self.failed = failed
        self.canceled = canceled
    }
}
