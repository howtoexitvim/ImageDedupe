import Foundation

/// Formats domain values for display.
///
/// The browser previously showed the raw ImageCaptureCore timestamp — an ISO 8601 string
/// in UTC, like `2026-08-14T14:38:02.000Z`. That is neither the user's locale nor their
/// time zone, so a photo taken at breakfast could appear to have been taken at lunch.
///
/// Locale and time zone are injected rather than read from `.current` so the behaviour is
/// testable and does not silently change with the machine running the tests.
public struct MediaDisplayFormat: Sendable {
    private let locale: Locale
    private let timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    // MARK: - Timestamp

    /// Converts a device timestamp into a localized date and time.
    ///
    /// Returns `nil` only when there is nothing to show. An unparseable value falls back to
    /// itself: showing whatever the device reported is more useful to the user, and more
    /// diagnosable, than an empty cell.
    public func timestamp(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        guard let date = Self.parse(rawValue) else { return rawValue }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Devices report with and without fractional seconds, so both are accepted.
    private static func parse(_ rawValue: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: rawValue) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: rawValue)
    }

    // MARK: - Duration

    /// `m:ss`, or `h:mm:ss` once the clip passes an hour.
    public func duration(_ seconds: Double?) -> String? {
        guard let seconds else { return nil }
        let total = max(0, Int(seconds.rounded()))

        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    // MARK: - File size

    public func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
