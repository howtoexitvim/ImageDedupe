import Testing
@testable import DeduperCore

@Test func sortsBySizeDescending() {
    let files = [
        DeviceMediaFile(id: "a", name: "A.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "b", name: "B.JPG", kind: "JPG", size: 30, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "c", name: "C.JPG", kind: "JPG", size: 20, timestamp: nil, width: nil, height: nil),
    ]

    let sorted = MediaSortDescriptor(field: .size, order: .descending).sorted(files)

    #expect(sorted.map(\.id) == ["b", "c", "a"])
}

@Test func sortsByNameAscendingCaseInsensitive() {
    let files = [
        DeviceMediaFile(id: "b", name: "beta.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "a", name: "Alpha.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
    ]

    let sorted = MediaSortDescriptor(field: .name, order: .ascending).sorted(files)

    #expect(sorted.map(\.id) == ["a", "b"])
}

@Test func sortsNamesUsingNaturalLocalizedOrder() {
    let files = [
        DeviceMediaFile(id: "10", name: "IMG_10.HEIC", kind: "HEIC", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "9", name: "IMG_09.HEIC", kind: "HEIC", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "2", name: "IMG_2.HEIC", kind: "HEIC", size: 10, timestamp: nil, width: nil, height: nil),
    ]

    let sorted = MediaSortDescriptor(field: .name, order: .ascending).sorted(files)

    #expect(sorted.map(\.id) == ["2", "9", "10"])
}

@Test func sortUsesIdAsStableTieBreaker() {
    let files = [
        DeviceMediaFile(id: "b", name: "Same.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "a", name: "Same.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
    ]

    let sorted = MediaSortDescriptor(field: .name, order: .ascending).sorted(files)

    #expect(sorted.map(\.id) == ["a", "b"])
}
