import AppKit
import XCTest
@testable import DeviceMediaKit

final class InspectorPreviewProviderTests: XCTestCase {
    func testUnknownDimensionsUseThe2048Ceiling() {
        XCTAssertEqual(
            InspectorPreviewProvider.requestedMaxPixelSize(width: nil, height: nil),
            2_048
        )
    }

    func testSmallSourceIsNeverRequestedLargerThanItsLongestEdge() {
        XCTAssertEqual(
            InspectorPreviewProvider.requestedMaxPixelSize(width: 640, height: 480),
            640
        )
    }

    func testLargeSourceIsCappedAt2048() {
        XCTAssertEqual(
            InspectorPreviewProvider.requestedMaxPixelSize(width: 8_064, height: 6_048),
            2_048
        )
    }

    func testDecodeDoesNotUpscaleASmallJPEG() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 320,
            pixelsHigh: 240,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))

        let decoded = try XCTUnwrap(
            InspectorPreviewProvider.decode(data, maxPixelSize: 2_048)
        )

        let representation = try XCTUnwrap(decoded.representations.first)
        XCTAssertLessThanOrEqual(representation.pixelsWide, 320)
        XCTAssertLessThanOrEqual(representation.pixelsHigh, 240)
    }
}
