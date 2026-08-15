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

    mutating func insert(_ file: DeviceCatalogFile) -> Bool {
        guard filenamesByToken[file.token] == nil else { return false }

        // The UI keys dictionaries by `model.id`, and `Dictionary(uniqueKeysWithValues:)`
        // traps on a repeat — the crash reported on 2026-08-15 after deleting several
        // photos, where two files shared the unassigned object handle `0` and a name.
        //
        // `DeviceMediaFileIdentity` avoids that for every case it can see, but it is handed
        // one file at a time and cannot know what the rest of the catalog contains. This is
        // the only place with that view, so uniqueness is guaranteed here rather than
        // assumed: a device quirk must never be able to crash the app.
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
        filenamesByToken[resolved.token] = resolved.model.name
        return true
    }
}
