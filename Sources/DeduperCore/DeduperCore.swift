import Foundation

public struct DeviceMediaFile: Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let size: Int64
    public let timestamp: String?
    public let width: Int?
    public let height: Int?

    public init(
        id: String,
        name: String,
        kind: String,
        size: Int64,
        timestamp: String?,
        width: Int?,
        height: Int?
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.timestamp = timestamp
        self.width = width
        self.height = height
    }
}

public enum DuplicateRule: String, Sendable {
    case nameKindSize
    case timestampKindSize
}

public struct DuplicatePlan: Sendable {
    public let keep: [DeviceMediaFile]
    public let delete: [DeviceMediaFile]
}

public enum DuplicatePlanner {
    public static func plan(files: [DeviceMediaFile], rule: DuplicateRule) -> DuplicatePlan {
        var seen: [String: DeviceMediaFile] = [:]
        var keep: [DeviceMediaFile] = []
        var delete: [DeviceMediaFile] = []

        for file in files {
            guard let key = key(for: file, rule: rule) else {
                keep.append(file)
                continue
            }

            if seen[key] != nil {
                delete.append(file)
            } else {
                seen[key] = file
                keep.append(file)
            }
        }

        return DuplicatePlan(keep: keep, delete: delete)
    }

    private static func key(for file: DeviceMediaFile, rule: DuplicateRule) -> String? {
        switch rule {
        case .nameKindSize:
            return "\(file.name.lowercased())|\(file.kind.uppercased())|\(file.size)"
        case .timestampKindSize:
            guard let timestamp = file.timestamp, !timestamp.isEmpty else {
                return nil
            }
            return "\(timestamp)|\(file.kind.uppercased())|\(file.size)"
        }
    }
}

public enum OpenSessionRetry {
    public static func shouldRetry(domain: String, code: Int, description: String) -> Bool {
        domain == "com.apple.ImageCaptureCore"
            && code == -9943
            && (description as NSString).range(of: "unlock", options: .caseInsensitive).location != NSNotFound
    }
}

public enum DeleteRequestPolicy {
    public static func shouldCallDeviceDelete(plannedDeleteCount: Int) -> Bool {
        plannedDeleteCount > 0
    }
}
