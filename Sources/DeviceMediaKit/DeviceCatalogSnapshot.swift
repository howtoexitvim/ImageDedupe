import DeduperCore
import Foundation

public struct DeviceCatalogFile: Equatable, Codable, Sendable {
    public let model: DeviceMediaFile
    public let token: DeviceFileToken

    public init(model: DeviceMediaFile, token: DeviceFileToken) {
        self.model = model
        self.token = token
    }
}

public struct DeviceCatalogSnapshot: Equatable, Codable, Sendable {
    public let generation: UUID
    public let deviceName: String
    public let deviceIdentityHash: String?
    public let files: [DeviceCatalogFile]

    /// Entries the framework listed before de-duplication, so a caller can tell a genuinely
    /// small catalog from a truncated one.
    public let sourceFileCount: Int

    public init(
        generation: UUID,
        deviceName: String,
        deviceIdentityHash: String? = nil,
        files: [DeviceCatalogFile],
        sourceFileCount: Int? = nil
    ) {
        self.generation = generation
        self.deviceName = deviceName
        self.deviceIdentityHash = deviceIdentityHash
        self.files = files
        self.sourceFileCount = sourceFileCount ?? files.count
    }
}

struct DeviceCatalogIndex {
    private(set) var files: [DeviceCatalogFile] = []
    private(set) var filenamesByToken: [DeviceFileToken: String] = [:]
    /// Model ids already used, so the catalog cannot contain two files sharing one.
    private var usedModelIDs: Set<String> = []

    /// Adds a file to the catalog. Only an exact re-report of the *same* framework entry is
    /// rejected; two genuinely separate files are always both kept.
    ///
    /// This used to drop any file whose token repeated. On a device where ImageCaptureCore
    /// assigns no object handles — every entry carries the unassigned `0` — a token
    /// degenerates to its fingerprint, so two real files with the same name, kind, size, and
    /// timestamp collided and the second was discarded. Measured on 2026-08-16: the
    /// framework listed 3,978 entries and the catalog kept 3,952.
    ///
    /// Those 26 were duplicates, which is precisely what this app exists to find. Dropping
    /// them is worse than any display fault: the user is told they have no duplicates exactly
    /// when they do. Uniqueness is still guaranteed, but by disambiguating ids rather than by
    /// throwing files away.
    mutating func insert(_ file: DeviceCatalogFile) -> Bool {
        // The UI keys dictionaries by `model.id`, and `Dictionary(uniqueKeysWithValues:)`
        // traps on a repeat — the crash reported on 2026-08-15. `DeviceMediaFileIdentity` is
        // handed one file at a time and cannot see the rest of the catalog; this is the only
        // place that can, so uniqueness is guaranteed here.
        var resolved = file
        if usedModelIDs.contains(file.model.id) {
            var candidate = file.model.id
            var suffix = 2
            while usedModelIDs.contains(candidate) {
                candidate = "\(file.model.id)#\(suffix)"
                suffix += 1
            }
            resolved = DeviceCatalogFile(
                model: file.model.withID(candidate),
                token: file.token
            )
        }

        usedModelIDs.insert(resolved.model.id)
        files.append(resolved)
        // Keyed by token, so download and delete can still resolve a filename. Where two
        // files share a token the first name wins; they are identical by definition of the
        // fingerprint, so the value is the same either way.
        if filenamesByToken[resolved.token] == nil {
            filenamesByToken[resolved.token] = resolved.model.name
        }
        return true
    }
}
