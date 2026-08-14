import DeduperCore
import DeviceMediaKit
import Foundation

struct Options {
    var rule: DuplicateRule = .nameKindSize
    var csvPath: String?
    var delete = false
    var confirmedDeviceDelete = false
    var deviceNameContains: String?
    var timeoutSeconds: TimeInterval = 120
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

@main
struct IPhoneDedupe {
    static func main() {
        do {
            let options = try parseOptions(CommandLine.arguments)
            let scanner = DeviceSessionController(
                deviceNameContains: options.deviceNameContains,
                timeoutSeconds: options.timeoutSeconds
            )
            let scan = try scanner.scan()
            let models = scan.files.map(\.model)
            let plan = DuplicatePlanner.plan(files: models, rule: options.rule)
            let deleteIDs = Set(plan.delete.map(\.id))
            let filesToDelete = scan.files.filter { deleteIDs.contains($0.model.id) }
            let csvURL = URL(fileURLWithPath: options.csvPath ?? defaultCSVPath())
            try writeCSV(models, plan: plan, to: csvURL)

            print("Device: \(scan.deviceName)")
            print("Files scanned: \(scan.files.count)")
            print("Rule: \(options.rule.rawValue)")
            print("Duplicates planned for deletion: \(filesToDelete.count)")
            print("CSV: \(csvURL.path)")

            if options.delete {
                if DeleteRequestPolicy.shouldCallDeviceDelete(plannedDeleteCount: filesToDelete.count) {
                    let summary = try scanner.delete(
                        filesToDelete.map(\.cameraFile),
                        from: scan.device,
                        confirmed: options.confirmedDeviceDelete
                    )
                    print("Deleted from device: \(summary.successful.count)")
                    print("Failed: \(summary.failed.count), canceled: \(summary.canceled.count)")
                    if let error = summary.error {
                        print("Delete API error: \(error)")
                        Foundation.exit(2)
                    }
                } else {
                    print("Deleted from device: 0")
                    print("Failed: 0, canceled: 0")
                    print("No duplicate files matched; skipped device delete request.")
                }
            } else {
                print("Dry run only. Add --delete --i-understand-this-deletes-from-device to delete.")
            }
        } catch {
            fputs("iphone-dedupe: \(error)\n\n\(usage())\n", stderr)
            Foundation.exit(1)
        }
    }
}

private func parseOptions(_ args: [String]) throws -> Options {
    var options = Options()
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--rule":
            index += 1
            guard index < args.count else { throw CLIError.usage("--rule requires a value") }
            switch args[index] {
            case "name-kind-size":
                options.rule = .nameKindSize
            case "timestamp-kind-size":
                options.rule = .timestampKindSize
            default:
                throw CLIError.usage("Unknown rule: \(args[index])")
            }
        case "--csv":
            index += 1
            guard index < args.count else { throw CLIError.usage("--csv requires a path") }
            options.csvPath = args[index]
        case "--delete":
            options.delete = true
        case "--i-understand-this-deletes-from-device":
            options.confirmedDeviceDelete = true
        case "--device-name-contains":
            index += 1
            guard index < args.count else { throw CLIError.usage("--device-name-contains requires text") }
            options.deviceNameContains = args[index]
        case "--timeout":
            index += 1
            guard index < args.count, let timeout = TimeInterval(args[index]) else {
                throw CLIError.usage("--timeout requires seconds")
            }
            options.timeoutSeconds = timeout
        case "--help", "-h":
            print(usage())
            Foundation.exit(0)
        default:
            throw CLIError.usage("Unknown argument: \(arg)")
        }
        index += 1
    }
    return options
}

private func usage() -> String {
    """
    Usage:
      iphone-dedupe [--rule name-kind-size|timestamp-kind-size] [--csv path] [--device-name-contains text]
      iphone-dedupe --delete --i-understand-this-deletes-from-device [same options]

    Defaults to dry run and rule=name-kind-size.
    """
}

private func defaultCSVPath() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let name = "iphone-dedupe-\(formatter.string(from: Date())).csv"
    return FileManager.default.currentDirectoryPath + "/" + name
}

private func writeCSV(_ files: [DeviceMediaFile], plan: DuplicatePlan, to url: URL) throws {
    let deleteIDs = Set(plan.delete.map(\.id))
    let keepIDs = Set(plan.keep.map(\.id))
    var lines = ["action,id,name,kind,size,timestamp,width,height"]

    for file in files {
        let action: String
        if deleteIDs.contains(file.id) {
            action = "would_delete"
        } else if keepIDs.contains(file.id) {
            action = "keep"
        } else {
            action = "unknown"
        }
        lines.append([
            action,
            file.id,
            file.name,
            file.kind,
            String(file.size),
            file.timestamp ?? "",
            file.width.map(String.init) ?? "",
            file.height.map(String.init) ?? "",
        ].map(csvEscape).joined(separator: ","))
    }

    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}
