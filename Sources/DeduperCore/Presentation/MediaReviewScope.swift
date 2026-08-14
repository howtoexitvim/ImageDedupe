public enum MediaReviewScope: String, CaseIterable, Identifiable, Sendable {
    case allMedia
    case duplicates

    public var id: String { rawValue }

    public func apply(to files: [DeviceMediaFile], duplicatePlan: DuplicatePlan) -> [DeviceMediaFile] {
        switch self {
        case .allMedia:
            return files
        case .duplicates:
            let deleteIDs = Set(duplicatePlan.delete.map(\.id))
            return files.filter { deleteIDs.contains($0.id) }
        }
    }
}
