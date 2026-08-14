public struct DuplicatePlan: Sendable {
    public let keep: [DeviceMediaFile]
    public let delete: [DeviceMediaFile]

    public init(keep: [DeviceMediaFile], delete: [DeviceMediaFile]) {
        self.keep = keep
        self.delete = delete
    }
}
