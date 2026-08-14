import Testing
@testable import DeduperCore

@Test func mediaQueryAppliesFiltersThenSorts() {
    let files = [
        DeviceMediaFile(id: "a", name: "IMG_1.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "b", name: "IMG_2.HEIC", kind: "HEIC", size: 30, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "c", name: "IMG_3.JPG", kind: "JPG", size: 20, timestamp: nil, width: nil, height: nil),
    ]

    let query = MediaQuery(
        filters: [.kindIn(["JPG"])],
        sort: MediaSortDescriptor(field: .size, order: .descending)
    )

    #expect(query.apply(to: files).map(\.id) == ["c", "a"])
}

@Test func emptyMediaQueryKeepsOriginalOrder() {
    let files = [
        DeviceMediaFile(id: "b", name: "B.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "a", name: "A.JPG", kind: "JPG", size: 20, timestamp: nil, width: nil, height: nil),
    ]

    #expect(MediaQuery().apply(to: files).map(\.id) == ["b", "a"])
}
