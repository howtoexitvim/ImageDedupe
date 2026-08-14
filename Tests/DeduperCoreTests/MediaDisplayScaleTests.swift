import Testing
@testable import DeduperCore

struct MediaDisplayScaleTests {
    @Test func clampsScaleAndDerivesStableThumbnailSizes() {
        let compact = MediaDisplayScale(rawValue: 0.2)
        #expect(compact.value == 0.75)
        #expect(compact.listThumbnailSide == 26)
        #expect(compact.gridMinimumSide == 92)

        let spacious = MediaDisplayScale(rawValue: 2.0)
        #expect(spacious.value == 1.6)
        #expect(spacious.listThumbnailSide == 46)
        #expect(spacious.gridMinimumSide == 176)
    }
}
