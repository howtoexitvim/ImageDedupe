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

    /// The directory this app stores its history in, named after the app.
    static let storeDirectoryName = "Image Dedupe"

    /// Directories earlier names used. Read once, to carry history across a rename.
    static let legacyStoreDirectoryNames = ["iPhone Dedupe"]

    private static let storeFilename = "operation-results.json"

    static func applicationSupport(fileManager: FileManager = .default) -> OperationResultStore {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return OperationResultStore(fileURL: resolveStoreURL(in: root))
    }

    /// The store to use, adopting history from a previous app name if this is the first run
    /// after a rename.
    ///
    /// Delete audits record what was removed from a device. Renaming the app without moving
    /// them would leave the records on disk but invisible to the app, which reads as data
    /// loss at exactly the moment a user is least able to tell a rename from a bug.
    ///
    /// Two deliberate choices:
    ///
    /// - Existing data under the current name **always wins**. Copying older history over
    ///   newer history would destroy the newer records, which is worse than not migrating.
    /// - The legacy file is **copied, not moved**. A copy costs a few kilobytes; an
    ///   interrupted move could leave the audit trail in neither place.
    static func resolveStoreURL(
        in root: URL,
        currentDirectory: String = storeDirectoryName,
        legacyDirectories: [String] = legacyStoreDirectoryNames,
        fileManager: FileManager = .default
    ) -> URL {
        let current = root
            .appendingPathComponent(currentDirectory, isDirectory: true)
            .appendingPathComponent(storeFilename)

        guard !fileManager.fileExists(atPath: current.path) else { return current }

        for legacyName in legacyDirectories {
            let legacy = root
                .appendingPathComponent(legacyName, isDirectory: true)
                .appendingPathComponent(storeFilename)
            guard fileManager.fileExists(atPath: legacy.path) else { continue }

            do {
                try fileManager.createDirectory(
                    at: current.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try fileManager.copyItem(at: legacy, to: current)
            } catch {
                // Migration is best-effort: if it fails the app still works, just without the
                // older history, and the original is untouched for a later attempt.
                continue
            }
            return current
        }

        return current
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
