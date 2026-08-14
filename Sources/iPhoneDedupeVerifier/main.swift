import DeduperCore
import DeviceMediaKit
import Foundation

private enum CommandError: Error, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingValue(String)
    case deleteNotConfirmed
    case unsafeMatchCount(Int)

    var description: String {
        switch self {
        case .missingCommand:
            return "Missing command. Use scan, find-exact-name, inspect-location, or delete-exact-name."
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .deleteNotConfirmed:
            return "Deletion requires --delete and --i-understand-this-deletes-from-device."
        case .unsafeMatchCount(let count):
            return "Refusing to delete because exact-name match count is \(count), not 1."
        }
    }
}

private struct Arguments {
    let command: String
    let targetName: String?
    let timeout: TimeInterval
    let destination: URL?
    let delete: Bool
    let confirmed: Bool

    static func parse(_ raw: [String]) throws -> Arguments {
        guard let command = raw.first else {
            throw CommandError.missingCommand
        }

        var targetName: String?
        var timeout: TimeInterval = 180
        var destination: URL?
        var delete = false
        var confirmed = false
        var index = 1

        while index < raw.count {
            let arg = raw[index]
            switch arg {
            case "--target-name":
                guard index + 1 < raw.count else {
                    throw CommandError.missingValue(arg)
                }
                targetName = raw[index + 1]
                index += 2
            case "--timeout":
                guard index + 1 < raw.count else {
                    throw CommandError.missingValue(arg)
                }
                timeout = TimeInterval(raw[index + 1]) ?? timeout
                index += 2
            case "--destination":
                guard index + 1 < raw.count else {
                    throw CommandError.missingValue(arg)
                }
                destination = URL(fileURLWithPath: raw[index + 1])
                index += 2
            case "--delete":
                delete = true
                index += 1
            case "--i-understand-this-deletes-from-device":
                confirmed = true
                index += 1
            default:
                throw CommandError.unknownCommand(arg)
            }
        }

        return Arguments(
            command: command,
            targetName: targetName,
            timeout: timeout,
            destination: destination,
            delete: delete,
            confirmed: confirmed
        )
    }
}

private func printUsage() {
    print("""
    Usage:
      iPhoneDedupeVerifier scan [--timeout 180]
      iPhoneDedupeVerifier find-exact-name --target-name CJKU9084.PNG [--timeout 180]
      iPhoneDedupeVerifier inspect-location --target-name IMG_1309.HEIC [--timeout 180]
      iPhoneDedupeVerifier import-exact-name --target-name IMG_1128.HEIC --destination /tmp [--timeout 180]
      iPhoneDedupeVerifier delete-exact-name --target-name CJKU9084.PNG --delete --i-understand-this-deletes-from-device [--timeout 180]
    """)
}

private func scanWithRetry(timeout: TimeInterval, attempts: Int = 3, delaySeconds: TimeInterval = 3) throws -> DeviceScanResult {
    var lastError: Error?
    for attempt in 1...attempts {
        do {
            return try DeviceSessionController(timeoutSeconds: timeout).scan()
        } catch {
            lastError = error
            if attempt < attempts {
                fputs("warning: scan attempt \(attempt) failed: \(error). Retrying...\n", stderr)
                Thread.sleep(forTimeInterval: delaySeconds)
            }
        }
    }
    throw lastError ?? DeviceMediaError.noDevice
}

private func runScan(timeout: TimeInterval) throws {
    let result = try scanWithRetry(timeout: timeout)
    let files = result.files.map(\.model)
    let conservativePlan = DuplicatePlanner.plan(files: files, rule: .nameKindSize)
    let timestampPlan = DuplicatePlanner.plan(files: files, rule: .timestampKindSize)
    let query = MediaQuery(
        filters: [.kindIn(["PNG", "JPG", "JPEG", "HEIC", "MOV", "MP4"])],
        sort: MediaSortDescriptor(field: .timestamp, order: .descending)
    )
    let queried = query.apply(to: files)

    print("device=\(result.deviceName)")
    print("scanned=\(files.count)")
    print("queryChecked=\(queried.count)")
    print("nameKindSizeWouldDelete=\(conservativePlan.delete.count)")
    print("timestampKindSizeWouldDelete=\(timestampPlan.delete.count)")
    print("firstFive=")
    for file in queried.prefix(5) {
        print("- \(file.name) kind=\(file.kind) size=\(file.size) timestamp=\(file.timestamp ?? "unknown")")
    }
}

private func findExactName(_ args: Arguments) throws {
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }

    let result = try scanWithRetry(timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }
    print("device=\(result.deviceName)")
    print("scanned=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    for match in matches {
        print("match=\(match.model.name) kind=\(match.model.kind) size=\(match.model.size) timestamp=\(match.model.timestamp ?? "unknown") location=\(match.model.location ?? "unknown")")
    }
}

private func inspectLocation(_ args: Arguments) throws {
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }

    let result = try scanWithRetry(timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }
    print("device=\(result.deviceName)")
    print("scanned=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    guard let match = matches.first else {
        return
    }

    print("mapped.location=\(match.model.location ?? "unknown")")
    print("camera.gpsString=\(match.cameraFile.gpsString ?? "unknown")")
    print("camera.width=\(match.cameraFile.width)")
    print("camera.height=\(match.cameraFile.height)")
    print("requestingMetadata=true")

    guard let metadata = MetadataProvider.metadata(for: match.cameraFile, timeoutSeconds: 30) else {
        print("metadata=nil")
        return
    }

    print("metadata.keys=\(metadata.keys.map { String(describing: $0) }.sorted().joined(separator: ","))")
    printMetadataSection(metadata, key: "{GPS}")
    printMetadataSection(metadata, key: "GPS")
    printMetadataSection(metadata, key: "{Exif}")
    printMetadataSection(metadata, key: "Exif")
    printMetadataSection(metadata, key: "{TIFF}")
    printMetadataSection(metadata, key: "TIFF")
}

private func printMetadataSection(_ metadata: [AnyHashable: Any], key: String) {
    guard let section = metadata[key] else {
        return
    }
    print("metadata.\(key)=\(section)")
}

private func deleteExactName(_ args: Arguments) throws {
    guard args.delete, args.confirmed else {
        throw CommandError.deleteNotConfirmed
    }
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }

    let controller = DeviceSessionController(timeoutSeconds: args.timeout)
    let result = try scanWithRetry(timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }

    print("device=\(result.deviceName)")
    print("scannedBefore=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    for match in matches {
        print("match=\(match.model.name) kind=\(match.model.kind) size=\(match.model.size) timestamp=\(match.model.timestamp ?? "unknown")")
    }

    guard matches.count == 1 else {
        throw CommandError.unsafeMatchCount(matches.count)
    }

    let summary = try controller.delete(matches.map(\.cameraFile), from: result.device, confirmed: true)
    print("deleteSuccessful=\(summary.successful.count)")
    print("deleteFailed=\(summary.failed.count)")
    print("deleteCanceled=\(summary.canceled.count)")
    if let error = summary.error {
        print("deleteError=\(error)")
    }

    let after = try scanWithRetry(timeout: args.timeout)
    let remaining = after.files.filter { $0.model.name == targetName }
    print("scannedAfter=\(after.files.count)")
    print("remainingExactMatches=\(remaining.count)")
}

private func importExactName(_ args: Arguments) throws {
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }
    guard let destination = args.destination else {
        throw CommandError.missingValue("--destination")
    }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    let result = try scanWithRetry(timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }
    print("device=\(result.deviceName)")
    print("scanned=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    guard matches.count == 1 else {
        throw CommandError.unsafeMatchCount(matches.count)
    }

    let summary = DeviceImportController(timeoutSeconds: args.timeout).importFiles(matches.map(\.cameraFile), to: destination)
    print("importSuccessful=\(summary.successful.count)")
    print("importFailed=\(summary.failed.count)")
    for imported in summary.successful {
        print("imported=\(destination.appendingPathComponent(imported.filename).path)")
    }
    for failure in summary.failed {
        print("failure=\(failure.file.name ?? "unknown") error=\(failure.error)")
    }
}

do {
    let args = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    switch args.command {
    case "scan":
        try runScan(timeout: args.timeout)
    case "find-exact-name":
        try findExactName(args)
    case "inspect-location":
        try inspectLocation(args)
    case "import-exact-name":
        try importExactName(args)
    case "delete-exact-name":
        try deleteExactName(args)
    default:
        throw CommandError.unknownCommand(args.command)
    }
} catch {
    fputs("error: \(error)\n", stderr)
    printUsage()
    exit(1)
}
