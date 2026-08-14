import Foundation

public struct MediaMetadataSummary: Equatable, Sendable {
    public let location: String?
    public let aperture: String?
    public let colorSpace: String?
    public let shutterSpeed: String?
    public let maker: String?
    public let model: String?

    public init(
        location: String? = nil,
        aperture: String? = nil,
        colorSpace: String? = nil,
        shutterSpeed: String? = nil,
        maker: String? = nil,
        model: String? = nil
    ) {
        self.location = location
        self.aperture = aperture
        self.colorSpace = colorSpace
        self.shutterSpeed = shutterSpeed
        self.maker = maker
        self.model = model
    }

    public static func locationText(fromGPS gps: [String: Any]) -> String? {
        guard let latitude = number(gps["Latitude"]),
              let longitude = number(gps["Longitude"]) else {
            return nil
        }
        let latitudeRef = string(gps["LatitudeRef"]) ?? (latitude < 0 ? "S" : "N")
        let longitudeRef = string(gps["LongitudeRef"]) ?? (longitude < 0 ? "W" : "E")
        return "\(dms(abs(latitude))) \(latitudeRef) \(dms(abs(longitude))) \(longitudeRef)"
    }

    public static func apertureText(fromExif exif: [String: Any]) -> String? {
        guard let fNumber = number(exif["FNumber"]) else {
            return nil
        }
        return "f/\(trimmed(fNumber, maxFractionDigits: 1))"
    }

    public static func shutterText(fromExif exif: [String: Any]) -> String? {
        guard let exposureTime = number(exif["ExposureTime"]), exposureTime > 0 else {
            return nil
        }
        if exposureTime < 1 {
            return "1/\(Int((1 / exposureTime).rounded()))"
        }
        return "\(trimmed(exposureTime, maxFractionDigits: 2)) s"
    }

    public static func colorSpaceText(from metadata: [String: Any], exif: [String: Any]) -> String? {
        if let profileName = string(metadata["ProfileName"]) {
            return profileName
        }
        guard let colorSpace = number(exif["ColorSpace"]) else {
            return nil
        }
        return Int(colorSpace) == 1 ? "sRGB" : "Display P3"
    }

    private static func dms(_ value: Double) -> String {
        let degrees = Int(value)
        let minutesValue = (value - Double(degrees)) * 60
        let minutes = Int(minutesValue)
        let seconds = (minutesValue - Double(minutes)) * 60
        return "\(degrees)° \(minutes)' \(trimmed(seconds, maxFractionDigits: 3))\""
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func trimmed(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
