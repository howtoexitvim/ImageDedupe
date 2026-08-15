import XCTest
@testable import DeduperCore

/// Phase 7: values shown to the user are formatted for humans, not for machines.
///
/// The List and Inspector previously showed the raw ImageCaptureCore timestamp, e.g.
/// `2026-08-14T14:38:02.000Z` — an ISO string in UTC, which is neither the user's locale
/// nor their time zone.
final class MediaDisplayFormatTests: XCTestCase {
    private let formatter = MediaDisplayFormat(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "America/New_York")!
    )

    // MARK: - Timestamps

    func testIsoTimestampBecomesAReadableLocalDate() {
        let formatted = formatter.timestamp("2026-08-14T14:38:02.000Z")

        XCTAssertNotNil(formatted)
        XCTAssertFalse(formatted!.contains("T"), "no ISO separator should survive")
        XCTAssertFalse(formatted!.contains("Z"), "no UTC marker should survive")
    }

    /// The stored timestamp is UTC. Showing it unconverted misreports when a photo was
    /// taken by however many hours the user is offset.
    func testTimestampIsConvertedIntoTheGivenTimeZone() {
        // 14:38 UTC is 10:38 in New York during daylight saving.
        let formatted = formatter.timestamp("2026-08-14T14:38:02.000Z")
        XCTAssertTrue(formatted!.contains("10:38"), "got \(formatted!)")
    }

    func testTimestampRespectsLocale() {
        let german = MediaDisplayFormat(
            locale: Locale(identifier: "de_DE"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let formatted = german.timestamp("2026-08-14T14:38:02.000Z")

        XCTAssertNotNil(formatted)
        XCTAssertFalse(formatted!.isEmpty)
    }

    func testMissingTimestampProducesNil() {
        XCTAssertNil(formatter.timestamp(nil))
    }

    /// A device that reports something unparseable must not blank the column; showing the
    /// raw value is more useful than showing nothing.
    func testUnparseableTimestampFallsBackToTheRawValue() {
        XCTAssertEqual(formatter.timestamp("not-a-date"), "not-a-date")
    }

    func testEmptyTimestampProducesNil() {
        XCTAssertNil(formatter.timestamp(""))
    }

    func testTimestampWithoutFractionalSecondsIsAccepted() {
        XCTAssertNotNil(formatter.timestamp("2026-08-14T14:38:02Z"))
    }

    // MARK: - Duration

    func testDurationUsesMinutesAndSeconds() {
        XCTAssertEqual(formatter.duration(111), "1:51")
    }

    func testDurationPadsSeconds() {
        XCTAssertEqual(formatter.duration(65), "1:05")
    }

    func testDurationUnderAMinuteStillShowsZeroMinutes() {
        XCTAssertEqual(formatter.duration(9), "0:09")
    }

    func testDurationOverAnHourShowsHours() {
        XCTAssertEqual(formatter.duration(3_661), "1:01:01")
    }

    func testMissingDurationProducesNil() {
        XCTAssertNil(formatter.duration(nil))
    }

    func testZeroDurationIsShownRatherThanHidden() {
        XCTAssertEqual(formatter.duration(0), "0:00")
    }

    func testNegativeDurationIsTreatedAsZero() {
        XCTAssertEqual(formatter.duration(-5), "0:00")
    }

    // MARK: - File size

    func testFileSizeIsHumanReadable() {
        let formatted = formatter.fileSize(1_500_000)
        XCTAssertTrue(formatted.contains("MB"), "got \(formatted)")
    }

    func testZeroByteFileIsShown() {
        XCTAssertFalse(formatter.fileSize(0).isEmpty)
    }
}
