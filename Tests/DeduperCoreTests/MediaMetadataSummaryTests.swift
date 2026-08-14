import Testing
@testable import DeduperCore

@Test func formatsGPSCoordinatesAsImageCaptureStyleLocation() {
    let gps: [String: Any] = [
        "Latitude": "22.35246333333333",
        "LatitudeRef": "N",
        "Longitude": "113.5156383333333",
        "LongitudeRef": "E",
    ]

    #expect(MediaMetadataSummary.locationText(fromGPS: gps) == "22° 21' 8.868\" N 113° 30' 56.298\" E")
}
