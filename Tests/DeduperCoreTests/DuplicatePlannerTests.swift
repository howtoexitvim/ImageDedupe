import Testing
@testable import DeduperCore

@Test func groupsFilesByNameKindAndSizeAndKeepsOldestPath() {
    let files = [
        DeviceMediaFile(id: "a", name: "IMG_1.JPG", kind: "JPG", size: 120, timestamp: "2026-08-14 10:00:00", width: 100, height: 200),
        DeviceMediaFile(id: "b", name: "IMG_1.JPG", kind: "JPG", size: 120, timestamp: "2026-08-14 10:05:00", width: 100, height: 200),
        DeviceMediaFile(id: "c", name: "IMG_2.JPG", kind: "JPG", size: 120, timestamp: "2026-08-14 10:00:00", width: 100, height: 200),
    ]

    let plan = DuplicatePlanner.plan(files: files, rule: .nameKindSize)

    #expect(plan.keep.map(\.id) == ["a", "c"])
    #expect(plan.delete.map(\.id) == ["b"])
}

@Test func groupsFilesByTimestampKindAndSizeWithoutUsingName() {
    let files = [
        DeviceMediaFile(id: "a", name: "A.JPG", kind: "JPG", size: 120, timestamp: "2026-08-14 10:00:00", width: 100, height: 200),
        DeviceMediaFile(id: "b", name: "B.JPG", kind: "JPG", size: 120, timestamp: "2026-08-14 10:00:00", width: 100, height: 200),
        DeviceMediaFile(id: "c", name: "C.JPG", kind: "JPG", size: 130, timestamp: "2026-08-14 10:00:00", width: 100, height: 200),
    ]

    let plan = DuplicatePlanner.plan(files: files, rule: .timestampKindSize)

    #expect(plan.keep.map(\.id) == ["a", "c"])
    #expect(plan.delete.map(\.id) == ["b"])
}

@Test func ignoresMissingTimestampForTimestampRule() {
    let files = [
        DeviceMediaFile(id: "a", name: "A.MP4", kind: "MP4", size: 120, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "b", name: "B.MP4", kind: "MP4", size: 120, timestamp: nil, width: nil, height: nil),
    ]

    let plan = DuplicatePlanner.plan(files: files, rule: .timestampKindSize)

    #expect(plan.keep.map(\.id) == ["a", "b"])
    #expect(plan.delete.isEmpty)
}

@Test func retriesImageCaptureUnlockErrors() {
    #expect(OpenSessionRetry.shouldRetry(domain: "com.apple.ImageCaptureCore", code: -9943, description: "Please unlock \"iPhone\""))
    #expect(!OpenSessionRetry.shouldRetry(domain: "com.apple.ImageCaptureCore", code: -1, description: "Other error"))
    #expect(!OpenSessionRetry.shouldRetry(domain: "other.domain", code: -9943, description: "Please unlock \"iPhone\""))
}

@Test func skipsDeviceDeleteWhenThereAreNoPlannedFiles() {
    #expect(!DeleteRequestPolicy.shouldCallDeviceDelete(plannedDeleteCount: 0))
    #expect(DeleteRequestPolicy.shouldCallDeviceDelete(plannedDeleteCount: 1))
}

@Test func nameKindSizeRuleIsACompositeDefinition() {
    let fields = DuplicateRule.nameKindSize.definition.fields

    #expect(fields.map(\.field) == [.name, .kind, .size])
    #expect(fields[0].normalizers == [.lowercase])
    #expect(fields[1].normalizers == [.uppercase])
    #expect(fields[2].normalizers == [])
}

@Test func compositeDefinitionBuildsExpectedKey() {
    let file = DeviceMediaFile(
        id: "a",
        name: "Img_1.jpg",
        kind: "jpg",
        size: 120,
        timestamp: nil,
        width: nil,
        height: nil
    )

    #expect(DuplicateRule.nameKindSize.definition.key(for: file) == "img_1.jpg|JPG|120")
}
