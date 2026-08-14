import Foundation

public enum MediaSortField: String, Sendable {
    case name
    case kind
    case timestamp
    case size
    case width
    case height
    case duration
}

public enum SortOrder: String, Sendable {
    case ascending
    case descending
}

public struct MediaSortDescriptor: Equatable, Sendable {
    public let field: MediaSortField
    public let order: SortOrder

    public init(field: MediaSortField, order: SortOrder) {
        self.field = field
        self.order = order
    }

    public func sorted(_ files: [DeviceMediaFile]) -> [DeviceMediaFile] {
        files.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs)
            if comparison == .orderedSame {
                return lhs.id < rhs.id
            }

            switch order {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
    }

    private func compare(_ lhs: DeviceMediaFile, _ rhs: DeviceMediaFile) -> SortComparison {
        switch field {
        case .name:
            return compareStrings(lhs.name, rhs.name)
        case .kind:
            return compareStrings(lhs.kind, rhs.kind)
        case .timestamp:
            return compareOptionals(lhs.timestamp, rhs.timestamp)
        case .size:
            if lhs.size == rhs.size {
                return .orderedSame
            }
            return lhs.size < rhs.size ? .orderedAscending : .orderedDescending
        case .width:
            return compareOptionals(lhs.width, rhs.width)
        case .height:
            return compareOptionals(lhs.height, rhs.height)
        case .duration:
            return compareOptionals(lhs.duration, rhs.duration)
        }
    }

    private func compareStrings(_ lhs: String, _ rhs: String) -> SortComparison {
        let comparison = lhs.localizedStandardCompare(rhs)
        if comparison == .orderedSame {
            return .orderedSame
        }
        return comparison == .orderedAscending ? .orderedAscending : .orderedDescending
    }

    private func compareOptionals(_ lhs: String?, _ rhs: String?) -> SortComparison {
        switch (lhs, rhs) {
        case (.none, .none):
            return .orderedSame
        case (.none, .some):
            return .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case (.some(let left), .some(let right)):
            return compareStrings(left, right)
        }
    }

    private func compareOptionals<T: Comparable>(_ lhs: T?, _ rhs: T?) -> SortComparison {
        switch (lhs, rhs) {
        case (.none, .none):
            return .orderedSame
        case (.none, .some):
            return .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case (.some(let left), .some(let right)):
            if left == right {
                return .orderedSame
            }
            return left < right ? .orderedAscending : .orderedDescending
        }
    }
}

private enum SortComparison {
    case orderedAscending
    case orderedSame
    case orderedDescending
}
