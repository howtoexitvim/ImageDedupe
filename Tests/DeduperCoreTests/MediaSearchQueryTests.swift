import Testing
@testable import DeduperCore

@Test func smartSearchMatchesUnprefixedTextAgainstNameOnly() {
    let file = DeviceMediaFile(
        id: "1",
        name: "IMG_1128.asset",
        kind: "HEIC",
        size: 1_100_000,
        timestamp: "2026-05-04T13:05:54.000Z",
        width: 2316,
        height: 3088,
        location: "22° 21' 8.802\" N 113° 30' 54.57\" E"
    )

    #expect(MediaSearchQuery("1128").matches(file))
    #expect(!MediaSearchQuery("heic").matches(file))
    #expect(!MediaSearchQuery("113°").matches(file))
    #expect(MediaSearchQuery("kind:heic").matches(file))
    #expect(!MediaSearchQuery("mov").matches(file))
}

@Test func smartSearchSupportsFieldTokens() {
    let file = DeviceMediaFile(
        id: "1",
        name: "IMG_1128.HEIC",
        kind: "HEIC",
        size: 1_100_000,
        timestamp: nil,
        width: nil,
        height: nil,
        duration: 8.4
    )

    #expect(MediaSearchQuery("name:1128 kind:heic").matches(file))
    #expect(!MediaSearchQuery("name:1128 kind:jpg").matches(file))
}

@Test func smartSearchSupportsSizeAndDurationComparisons() {
    let file = DeviceMediaFile(
        id: "1",
        name: "clip.MOV",
        kind: "MOV",
        size: 2_500_000,
        timestamp: nil,
        width: nil,
        height: nil,
        duration: 12.2
    )

    #expect(MediaSearchQuery("size:>2mb duration:>10s").matches(file))
    #expect(MediaSearchQuery("size:<3mb duration:<13s").matches(file))
    #expect(!MediaSearchQuery("size:<2mb").matches(file))
    #expect(!MediaSearchQuery("duration:<10s").matches(file))
}
