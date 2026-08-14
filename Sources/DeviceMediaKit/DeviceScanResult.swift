import DeduperCore
import ImageCaptureCore

public struct DeviceScanResult {
    public let deviceName: String
    public let device: ICCameraDevice
    public let files: [(model: DeviceMediaFile, cameraFile: ICCameraFile)]

    public init(deviceName: String, device: ICCameraDevice, files: [(model: DeviceMediaFile, cameraFile: ICCameraFile)]) {
        self.deviceName = deviceName
        self.device = device
        self.files = files
    }
}
