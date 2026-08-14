import Testing
@testable import DeduperCore

@Test func nameContainsIsCaseInsensitive() {
    let file = DeviceMediaFile(
        id: "a",
        name: "IMG_1234.JPG",
        kind: "JPG",
        size: 10,
        timestamp: nil,
        width: nil,
        height: nil
    )

    #expect(MediaFilter.nameContains("img_").matches(file))
    #expect(MediaFilter.nameContains("1234").matches(file))
    #expect(!MediaFilter.nameContains("nope").matches(file))
}

@Test func kindFilterNormalizesInput() {
    let file = DeviceMediaFile(
        id: "a",
        name: "A.heic",
        kind: "heic",
        size: 10,
        timestamp: nil,
        width: nil,
        height: nil
    )

    #expect(MediaFilter.kindIn(["HEIC"]).matches(file))
    #expect(MediaFilter.kindIn(["heic"]).matches(file))
    #expect(!MediaFilter.kindIn(["JPG"]).matches(file))
}

@Test func sizeRangeAllowsOpenBounds() {
    let file = DeviceMediaFile(
        id: "a",
        name: "A.MOV",
        kind: "MOV",
        size: 100,
        timestamp: nil,
        width: nil,
        height: nil
    )

    #expect(MediaFilter.sizeBetween(min: nil, max: 100).matches(file))
    #expect(MediaFilter.sizeBetween(min: 100, max: nil).matches(file))
    #expect(MediaFilter.sizeBetween(min: 50, max: 150).matches(file))
    #expect(!MediaFilter.sizeBetween(min: 101, max: nil).matches(file))
    #expect(!MediaFilter.sizeBetween(min: nil, max: 99).matches(file))
}
