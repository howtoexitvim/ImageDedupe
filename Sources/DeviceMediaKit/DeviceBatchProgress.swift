import Foundation

/// A small Sendable snapshot, rather than exposing mutable Foundation `Progress`
/// across the package boundary.
public struct DeviceBatchProgress: Equatable, Sendable {
    public let completedItems: Int
    public let totalItems: Int
    public let currentFilename: String?
    public let fractionCompleted: Double

    public init(
        completedItems: Int,
        totalItems: Int,
        currentFilename: String?,
        fractionCompleted: Double
    ) {
        let normalizedTotal = max(0, totalItems)
        self.totalItems = normalizedTotal
        self.completedItems = min(max(0, completedItems), normalizedTotal)
        self.currentFilename = currentFilename
        self.fractionCompleted = min(max(0, fractionCompleted), 1)
    }
}
