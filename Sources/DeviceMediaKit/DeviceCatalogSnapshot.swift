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

    public init(
        generation: UUID,
        deviceName: String,
        deviceIdentityHash: String? = nil,
        files: [DeviceCatalogFile]
    ) {
        self.generation = generation
        self.deviceName = deviceName
        self.deviceIdentityHash = deviceIdentityHash
        self.files = files
    }
}

struct DeviceCatalogIndex {
    private(set) var files: [DeviceCatalogFile] = []
    private(set) var filenamesByToken: [DeviceFileToken: String] = [:]

    mutating func insert(_ file: DeviceCatalogFile) -> Bool {
        guard filenamesByToken[file.token] == nil else { return false }
        files.append(file)
        filenamesByToken[file.token] = file.model.name
        return true
    }
}
