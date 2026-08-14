public enum DeviceMediaError: Error, CustomStringConvertible {
    case noDevice
    case openFailed(String)
    case timeout(String)
    case deleteNotConfirmed

    public var description: String {
        switch self {
        case .noDevice:
            return "No ImageCaptureCore camera device found. Connect and unlock the iPhone, then trust this Mac."
        case .openFailed(let message), .timeout(let message):
            return message
        case .deleteNotConfirmed:
            return "Refusing to delete. Explicit deletion confirmation is required."
        }
    }
}
