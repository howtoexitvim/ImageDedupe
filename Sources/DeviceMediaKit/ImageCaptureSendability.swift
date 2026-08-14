@preconcurrency import AppKit
@preconcurrency import ImageCaptureCore

extension ICCameraDevice: @unchecked @retroactive Sendable {}
extension ICCameraFile: @unchecked @retroactive Sendable {}
extension NSImage: @unchecked @retroactive Sendable {}
extension DeviceScanResult: @unchecked Sendable {}
extension DeviceDeleteSummary: @unchecked Sendable {}
