import XCTest
@testable import DeduperCore

/// Phase 7: VoiceOver announces the same information in List and Grid.
final class MediaAccessibilityLabelTests: XCTestCase {
    private let format = MediaDisplayFormat(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "UTC")!
    )

    private func file(
        name: String = "IMG_0001.HEIC",
        kind: String = "heic",
        size: Int64 = 2_000_000,
        timestamp: String? = "2026-08-14T14:38:02.000Z",
        duration: Double? = nil
    ) -> DeviceMediaFile {
        DeviceMediaFile(
            id: name, name: name, kind: kind, size: size,
            timestamp: timestamp, width: nil, height: nil, duration: duration
        )
    }

    func testLabelLeadsWithTheFilename() {
        let label = MediaAccessibilityLabel.describe(file(), format: format)
        XCTAssertTrue(label.hasPrefix("IMG_0001.HEIC"), label)
    }

    func testLabelIncludesKindAndSize() {
        let label = MediaAccessibilityLabel.describe(file(), format: format)
        XCTAssertTrue(label.contains("HEIC"), label)
        XCTAssertTrue(label.contains("MB"), label)
    }

    /// The spoken date must be the readable one, not the raw ISO string.
    func testLabelSpeaksAReadableDate() {
        let label = MediaAccessibilityLabel.describe(file(), format: format)
        XCTAssertFalse(label.contains("2026-08-14T14:38:02.000Z"), label)
        XCTAssertTrue(label.contains("2026"), label)
    }

    func testDurationIsAnnouncedForVideo() {
        let label = MediaAccessibilityLabel.describe(
            file(name: "CLIP.MOV", kind: "mov", duration: 111),
            format: format
        )
        XCTAssertTrue(label.contains("duration 1:51"), label)
    }

    func testDurationIsOmittedForStills() {
        let label = MediaAccessibilityLabel.describe(file(), format: format)
        XCTAssertFalse(label.contains("duration"), label)
    }

    /// Selection state is stated in both directions: "not selected" matters when the user
    /// is checking what a delete will act on.
    func testSelectionIsAlwaysAnnounced() {
        let selected = MediaAccessibilityLabel.describe(file(), format: format, isSelected: true)
        let unselected = MediaAccessibilityLabel.describe(file(), format: format, isSelected: false)

        XCTAssertTrue(selected.hasSuffix("selected"), selected)
        XCTAssertTrue(unselected.hasSuffix("not selected"), unselected)
    }

    func testImportedStateIsAnnounced() {
        let label = MediaAccessibilityLabel.describe(file(), format: format, isImported: true)
        XCTAssertTrue(label.contains("imported"), label)
    }

    func testDuplicateCandidateIsAnnounced() {
        let label = MediaAccessibilityLabel.describe(file(), format: format, isDuplicateCandidate: true)
        XCTAssertTrue(label.contains("duplicate candidate"), label)
    }

    func testMissingTimestampIsSimplyOmitted() {
        let label = MediaAccessibilityLabel.describe(file(timestamp: nil), format: format)
        XCTAssertFalse(label.contains(", ,"), "no empty segments: \(label)")
        XCTAssertTrue(label.hasPrefix("IMG_0001.HEIC"), label)
    }

    func testLabelHasNoEmptySegments() {
        let label = MediaAccessibilityLabel.describe(
            file(timestamp: nil, duration: nil),
            format: format
        )
        for segment in label.components(separatedBy: ", ") {
            XCTAssertFalse(segment.trimmingCharacters(in: .whitespaces).isEmpty, label)
        }
    }
}
