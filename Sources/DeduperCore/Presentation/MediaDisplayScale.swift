import Foundation

public struct MediaDisplayScale: Equatable, Sendable {
    public let value: Double

    public init(rawValue: Double) {
        value = min(max(rawValue, 0.75), 1.6)
    }

    public var listThumbnailSide: Double {
        (8 + (24 * value)).rounded()
    }

    public var gridMinimumSide: Double {
        (18 + (99 * value)).rounded()
    }

    public var gridMaximumSide: Double {
        gridMinimumSide + 38
    }

    public var gridThumbnailHeight: Double {
        (gridMinimumSide * 0.82).rounded()
    }
}
