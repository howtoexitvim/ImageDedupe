import ImageCaptureCore

public struct DeviceDeleteSummary {
    public var successful: [ICCameraFile]
    public var failed: [ICCameraFile]
    public var canceled: [ICCameraFile]
    public var error: Error?

    public init(
        successful: [ICCameraFile],
        failed: [ICCameraFile],
        canceled: [ICCameraFile],
        error: Error?
    ) {
        self.successful = successful
        self.failed = failed
        self.canceled = canceled
        self.error = error
    }
}
