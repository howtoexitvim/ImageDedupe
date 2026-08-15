import Foundation

struct OperationResultStore {
    struct LoadResult: Equatable {
        let records: [OperationResultRecord]
        let warning: String?
    }

    let fileURL: URL
    let maximumRecordCount: Int

    init(fileURL: URL, maximumRecordCount: Int = 20) {
        self.fileURL = fileURL
        self.maximumRecordCount = max(1, maximumRecordCount)
    }

    static func applicationSupport(fileManager: FileManager = .default) -> OperationResultStore {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return OperationResultStore(
            fileURL: root
                .appendingPathComponent("iPhone Dedupe", isDirectory: true)
                .appendingPathComponent("operation-results.json")
        )
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(records: [], warning: nil)
        }

        do {
            try hardenExistingStoragePermissions()
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return LoadResult(records: try decoder.decode([OperationResultRecord].self, from: data), warning: nil)
        } catch {
            return LoadResult(
                records: [],
                warning: "Saved operation results could not be read. New results can still be saved."
            )
        }
    }

    @discardableResult
    func append(_ record: OperationResultRecord) throws -> [OperationResultRecord] {
        let existing = load().records
        guard record.shouldPersist else { return existing }

        let candidates = [record] + existing.filter { $0.id != record.id }
        let pendingCount = candidates.lazy.filter(\.isPendingDeleteAudit).count
        let resolvedSlots = max(0, maximumRecordCount - pendingCount)
        var acceptedResolved = 0
        let records = candidates.filter { candidate in
            if candidate.isPendingDeleteAudit { return true }
            guard acceptedResolved < resolvedSlots else { return false }
            acceptedResolved += 1
            return true
        }
        try save(records)
        return records
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let pending = load().records.filter(\.isPendingDeleteAudit)
        if pending.isEmpty {
            try FileManager.default.removeItem(at: fileURL)
        } else {
            try save(pending)
        }
    }

    private func save(_ records: [OperationResultRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try setPrivateDirectoryPermissions(at: directoryURL)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
        try setPrivateFilePermissions(at: fileURL)
    }

    private func hardenExistingStoragePermissions() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try setPrivateDirectoryPermissions(at: directoryURL)
        try setPrivateFilePermissions(at: fileURL)
    }

    private func setPrivateDirectoryPermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func setPrivateFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
