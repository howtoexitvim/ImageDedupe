public struct MediaQuery: Equatable, Sendable {
    public let filters: [MediaFilter]
    public let sort: MediaSortDescriptor?

    public init(filters: [MediaFilter] = [], sort: MediaSortDescriptor? = nil) {
        self.filters = filters
        self.sort = sort
    }

    public func apply(to files: [DeviceMediaFile]) -> [DeviceMediaFile] {
        let filtered = files.filter { file in
            filters.allSatisfy { $0.matches(file) }
        }

        guard let sort else {
            return filtered
        }

        return sort.sorted(filtered)
    }
}
