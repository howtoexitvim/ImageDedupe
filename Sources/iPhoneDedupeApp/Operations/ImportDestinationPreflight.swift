import Foundation
import DeviceMediaKit

struct ImportDestinationPreflight {
    struct Item: Equatable, Sendable {
        let filename: String
        let size: Int64
    }

    struct Facts: Equatable, Sendable {
        let isDirectory: Bool
        let isLocalVolume: Bool
        let isWritable: Bool
        let availableCapacity: Int64?
        let stagingSharesDestinationVolume: Bool
        let stagingAvailableCapacity: Int64?
        let existingFilenames: Set<String>

        init(
            isDirectory: Bool,
            isLocalVolume: Bool,
            isWritable: Bool,
            availableCapacity: Int64?,
            stagingSharesDestinationVolume: Bool,
            stagingAvailableCapacity: Int64?,
            existingFilenames: Set<String>
        ) {
            self.isDirectory = isDirectory
            self.isLocalVolume = isLocalVolume
            self.isWritable = isWritable
            self.availableCapacity = availableCapacity
            self.stagingSharesDestinationVolume = stagingSharesDestinationVolume
            self.stagingAvailableCapacity = stagingAvailableCapacity
            self.existingFilenames = existingFilenames
        }
    }

    enum Failure: Equatable, Sendable {
        case destinationUnavailable(String)
        case notDirectory
        case nonLocalVolume
        case notWritable
        case capacityUnavailable
        case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)
        case stagingCapacityUnavailable
        case insufficientStagingSpace(requiredBytes: Int64, availableBytes: Int64)
        case filenameCollisions([String])

        var message: String {
            switch self {
            case let .destinationUnavailable(reason):
                return "The destination could not be inspected: \(reason)"
            case .notDirectory:
                return "The import destination is not a folder."
            case .nonLocalVolume:
                return "Choose a folder on a local disk."
            case .notWritable:
                return "The destination folder is not writable."
            case .capacityUnavailable:
                return "Available disk space could not be verified."
            case let .insufficientSpace(requiredBytes, availableBytes):
                return "Not enough disk space. \(format(requiredBytes)) required; \(format(availableBytes)) available."
            case .stagingCapacityUnavailable:
                return "Available private staging space could not be verified."
            case let .insufficientStagingSpace(requiredBytes, availableBytes):
                return "Not enough private staging space. \(format(requiredBytes)) required; \(format(availableBytes)) available."
            case let .filenameCollisions(filenames):
                let preview = filenames.prefix(3).joined(separator: ", ")
                let remainder = filenames.count > 3 ? " and \(filenames.count - 3) more" : ""
                return "Existing or duplicate filenames would collide: \(preview)\(remainder). No files were overwritten."
            }
        }

        private func format(_ bytes: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    enum Outcome: Equatable, Sendable {
        case ready(requiredBytes: Int64, availableBytes: Int64)
        case blocked(Failure)
    }

    static func evaluate(items: [Item], facts: Facts) -> Outcome {
        guard facts.isDirectory else { return .blocked(.notDirectory) }
        guard facts.isLocalVolume else { return .blocked(.nonLocalVolume) }
        guard facts.isWritable else { return .blocked(.notWritable) }
        guard let availableCapacity = facts.availableCapacity else {
            return .blocked(.capacityUnavailable)
        }

        let finalBytes = items.reduce(Int64(0)) { total, item in
            let (sum, overflow) = total.addingReportingOverflow(max(0, item.size))
            return overflow ? Int64.max : sum
        }
        let largestItem = items.map { max(0, $0.size) }.max() ?? 0
        let requiredBytes: Int64
        if facts.stagingSharesDestinationVolume {
            let (peak, overflow) = finalBytes.addingReportingOverflow(largestItem)
            requiredBytes = overflow ? Int64.max : peak
        } else {
            requiredBytes = finalBytes
            guard let stagingAvailableCapacity = facts.stagingAvailableCapacity else {
                return .blocked(.stagingCapacityUnavailable)
            }
            guard stagingAvailableCapacity >= largestItem else {
                return .blocked(.insufficientStagingSpace(
                    requiredBytes: largestItem,
                    availableBytes: stagingAvailableCapacity
                ))
            }
        }
        guard availableCapacity >= requiredBytes else {
            return .blocked(.insufficientSpace(
                requiredBytes: requiredBytes,
                availableBytes: availableCapacity
            ))
        }

        let existing = Set(facts.existingFilenames.map(normalizedFilename))
        let grouped = Dictionary(grouping: items, by: { normalizedFilename($0.filename) })
        let collisions = grouped
            .filter { existing.contains($0.key) || $0.value.count > 1 }
            .flatMap { $0.value.map(\.filename) }
            .sorted()
        guard collisions.isEmpty else {
            return .blocked(.filenameCollisions(collisions))
        }

        return .ready(requiredBytes: requiredBytes, availableBytes: availableCapacity)
    }

    static func inspect(
        destination: URL,
        items: [Item],
        stagingRoot: URL = ImportStagingManager.applicationCaches().rootDirectory,
        fileManager: FileManager = .default
    ) -> Outcome {
        do {
            let values = try destination.resourceValues(forKeys: [
                .isDirectoryKey,
                .volumeIsLocalKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let filenames = try fileManager.contentsOfDirectory(atPath: destination.path)
            let stagingProbe = nearestExistingDirectory(to: stagingRoot, fileManager: fileManager)
            let stagingValues = try stagingProbe.resourceValues(forKeys: [
                .volumeIdentifierKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let destinationVolume = String(describing: values.volumeIdentifier)
            let stagingVolume = String(describing: stagingValues.volumeIdentifier)
            let facts = Facts(
                isDirectory: values.isDirectory == true,
                isLocalVolume: values.volumeIsLocal == true,
                isWritable: canCreateProbe(in: destination, fileManager: fileManager),
                availableCapacity: values.volumeAvailableCapacityForImportantUsage,
                stagingSharesDestinationVolume: destinationVolume == stagingVolume,
                stagingAvailableCapacity: stagingValues.volumeAvailableCapacityForImportantUsage,
                existingFilenames: Set(filenames)
            )
            return evaluate(items: items, facts: facts)
        } catch {
            return .blocked(.destinationUnavailable(error.localizedDescription))
        }
    }

    private static func normalizedFilename(_ filename: String) -> String {
        filename.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func canCreateProbe(in directory: URL, fileManager: FileManager) -> Bool {
        let probe = directory.appendingPathComponent(".iphone-dedupe-write-probe-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: probe.path, contents: Data()) else {
            return false
        }
        do {
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private static func nearestExistingDirectory(to url: URL, fileManager: FileManager) -> URL {
        var candidate = url.standardizedFileURL
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        return candidate
    }
}
