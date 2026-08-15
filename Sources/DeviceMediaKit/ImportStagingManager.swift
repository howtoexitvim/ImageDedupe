import Darwin
import Foundation

public enum ImportStagingError: Error, Equatable, LocalizedError, Sendable {
    case outsideRoot
    case missingMarker
    case filesystem(String)

    public var errorDescription: String? {
        switch self {
        case .outsideRoot:
            return "Refusing to clean a directory outside the import staging root."
        case .missingMarker:
            return "Refusing to clean an unmarked import staging directory."
        case .filesystem(let message):
            return message
        }
    }
}

public struct ImportStagingSession: Equatable, Sendable {
    public let directory: URL
    public let markerURL: URL
    public let identity: ImportDestinationIdentity
}

public struct ImportStagingManager: Sendable {
    public static let markerFilename = ".iphone-dedupe-staging"
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public static func applicationCaches(fileManager: FileManager = .default) -> ImportStagingManager {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return ImportStagingManager(rootDirectory: caches
            .appendingPathComponent("com.shuqi.iPhoneDedupe", isDirectory: true)
            .appendingPathComponent("Staging", isDirectory: true))
    }

    public func createSession(fileManager: FileManager = .default) throws -> ImportStagingSession {
        do {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
            let directory = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let marker = directory.appendingPathComponent(Self.markerFilename, isDirectory: false)
            guard fileManager.createFile(
                atPath: marker.path,
                contents: Data(String(getpid()).utf8),
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw ImportStagingError.filesystem("Could not create the staging marker.")
            }
            let identity = try ImportDestinationIdentity.capture(destination: directory)
            return ImportStagingSession(directory: directory, markerURL: marker, identity: identity)
        } catch let error as ImportStagingError {
            throw error
        } catch {
            throw ImportStagingError.filesystem(error.localizedDescription)
        }
    }

    /// Re-opens a staging session created by another process, for the device helper.
    ///
    /// The helper is told where to stage rather than choosing for itself, so the app keeps
    /// ownership of the destination and commit steps. That makes this an input from
    /// outside the process, and it is therefore **validated rather than trusted**: the
    /// directory must sit directly inside this manager's root, must be a real directory
    /// rather than a symbolic link, and must already carry the staging marker. Without
    /// those checks an unexpected path could redirect downloaded bytes somewhere the user
    /// never nominated.
    public func adoptSession(
        at directory: URL,
        fileManager: FileManager = .default
    ) throws -> ImportStagingSession {
        let standardized = directory.standardizedFileURL
        guard standardized.deletingLastPathComponent().standardizedFileURL == rootDirectory else {
            throw ImportStagingError.filesystem(
                "The staging directory is outside this application's staging root."
            )
        }

        let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw ImportStagingError.filesystem("The staging path is not a directory.")
        }

        let marker = standardized.appendingPathComponent(Self.markerFilename, isDirectory: false)
        guard fileManager.fileExists(atPath: marker.path) else {
            throw ImportStagingError.filesystem("The staging directory has no staging marker.")
        }

        let identity = try ImportDestinationIdentity.capture(destination: standardized)
        return ImportStagingSession(directory: standardized, markerURL: marker, identity: identity)
    }

    public func cleanup(_ session: ImportStagingSession, fileManager: FileManager = .default) throws {
        try cleanupDirectory(session.directory, fileManager: fileManager)
    }

    /// Removes only marked, immediate child directories left by earlier app runs.
    /// Unmarked entries and symbolic links are deliberately preserved.
    public func cleanupStaleSessions(
        olderThan cutoff: Date = Date().addingTimeInterval(-24 * 60 * 60),
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            throw ImportStagingError.filesystem(error.localizedDescription)
        }
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let marker = child.appendingPathComponent(Self.markerFilename, isDirectory: false)
            let markerValues = try? marker.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard markerValues?.isRegularFile == true,
                  markerValues?.isSymbolicLink != true,
                  let modificationDate = markerValues?.contentModificationDate,
                  modificationDate < cutoff else {
                continue
            }
            if markerOwnerIsAlive(marker, fileManager: fileManager) {
                continue
            }
            do {
                try cleanupDirectory(child, fileManager: fileManager)
            } catch ImportStagingError.missingMarker {
                continue
            }
        }
    }

    private func markerOwnerIsAlive(_ marker: URL, fileManager: FileManager) -> Bool {
        guard let data = fileManager.contents(atPath: marker.path),
              let text = String(data: data, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else {
            return false
        }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public func cleanupDirectory(_ directory: URL, fileManager: FileManager = .default) throws {
        let root = rootDirectory.standardizedFileURL
        let candidate = directory.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else {
            throw ImportStagingError.outsideRoot
        }
        let candidateValues = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard candidateValues?.isDirectory == true, candidateValues?.isSymbolicLink != true else {
            throw ImportStagingError.missingMarker
        }
        let marker = candidate.appendingPathComponent(Self.markerFilename, isDirectory: false)
        let markerValues = try? marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard markerValues?.isRegularFile == true, markerValues?.isSymbolicLink != true else {
            throw ImportStagingError.missingMarker
        }
        do {
            try fileManager.removeItem(at: candidate)
        } catch {
            throw ImportStagingError.filesystem(error.localizedDescription)
        }
    }
}
