import Testing
@testable import DeduperCore

@Test func reviewScopeFiltersDuplicateCandidates() {
    let files = [
        DeviceMediaFile(id: "keep", name: "A.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "delete", name: "A.JPG", kind: "JPG", size: 10, timestamp: nil, width: nil, height: nil),
        DeviceMediaFile(id: "other", name: "B.JPG", kind: "JPG", size: 20, timestamp: nil, width: nil, height: nil),
    ]
    let plan = DuplicatePlanner.plan(files: files, rule: .nameKindSize)

    #expect(MediaReviewScope.allMedia.apply(to: files, duplicatePlan: plan).map(\.id) == ["keep", "delete", "other"])
    #expect(MediaReviewScope.duplicates.apply(to: files, duplicatePlan: plan).map(\.id) == ["delete"])
}
