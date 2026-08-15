public enum MediaReviewScope: String, CaseIterable, Identifiable, Sendable {
    case allMedia
    case duplicates

    public var id: String { rawValue }

    /// - Parameter duplicateGroups: every copy of each duplicate set, in group order. When
    ///   supplied, Duplicates shows all of them rather than only the redundant ones, so the
    ///   copy that will survive can be seen and compared before anything is deleted.
    public func apply(
        to files: [DeviceMediaFile],
        duplicatePlan: DuplicatePlan,
        duplicateGroups: [DuplicateGrouping.Group] = []
    ) -> [DeviceMediaFile] {
        switch self {
        case .allMedia:
            return files
        case .duplicates:
            guard !duplicateGroups.isEmpty else {
                // No grouping supplied: fall back to the redundant copies alone.
                let deleteIDs = Set(duplicatePlan.delete.map(\.id))
                return files.filter { deleteIDs.contains($0.id) }
            }
            // Group order, not catalog order, so each set's copies sit next to each other
            // and the grid pairs them visibly instead of interleaving unrelated groups.
            return DuplicateGrouping.flattened(duplicateGroups)
        }
    }
}
