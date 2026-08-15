import Foundation

public struct DeviceOperationFailure: Equatable, Codable, Sendable {
    public let token: DeviceFileToken
    public let filename: String
    public let reason: String

    public init(token: DeviceFileToken, filename: String, reason: String) {
        self.token = token
        self.filename = filename
        self.reason = reason
    }
}

public struct DeviceDownloadSuccess: Equatable, Codable, Sendable {
    public let token: DeviceFileToken
    public let filename: String
    public let stagedIdentity: StagedFileIdentity

    public init(token: DeviceFileToken, filename: String, stagedIdentity: StagedFileIdentity) {
        self.token = token
        self.filename = filename
        self.stagedIdentity = stagedIdentity
    }
}

public struct DeviceGatewayImportSummary: Equatable, Codable, Sendable {
    public var successful: [DeviceDownloadSuccess]
    public var failed: [DeviceOperationFailure]
    public var canceled: [DeviceFileToken]

    public init(
        successful: [DeviceDownloadSuccess] = [],
        failed: [DeviceOperationFailure] = [],
        canceled: [DeviceFileToken] = []
    ) {
        self.successful = successful
        self.failed = failed
        self.canceled = canceled
    }
}

public struct DeviceGatewayDeleteSummary: Equatable, Codable, Sendable {
    public var successful: [DeviceFileToken]
    public var failed: [DeviceOperationFailure]
    public var canceled: [DeviceFileToken]

    public init(
        successful: [DeviceFileToken] = [],
        failed: [DeviceOperationFailure] = [],
        canceled: [DeviceFileToken] = []
    ) {
        self.successful = successful
        self.failed = failed
        self.canceled = canceled
    }
}
