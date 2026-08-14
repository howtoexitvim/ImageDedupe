import DeduperCore
import Foundation
import ImageCaptureCore

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
    case noDevice
    case deviceLocked(String)
    case openFailed(String)
    case timeout(String)
    case deleteNotConfirmed

    var description: String {
        switch self {
        case .usage(let message), .deviceLocked(let message), .openFailed(let message), .timeout(let message):
            return message
        case .noDevice:
            return "No ImageCaptureCore camera device found. Connect and unlock the iPhone, then trust this Mac."
        case .deleteNotConfirmed:
            return "Refusing to delete. Add both --delete and --i-understand-this-deletes-from-device."
        }
    }
}

final class CameraScanner: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let options: Options
    private let browser = ICDeviceBrowser()
    private var selectedDevice: ICCameraDevice?
    private var openError: Error?
    private var isReady = false
    private var removed = false

    init(options: Options) {
        self.options = options
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
    }

    func scan() throws -> (device: ICCameraDevice, files: [(DeviceMediaFile, ICCameraFile)]) {
        browser.start()
        defer { browser.stop() }

        let deadline = Date().addingTimeInterval(options.timeoutSeconds)
        while selectedDevice == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        guard let device = selectedDevice else {
            throw CLIError.noDevice
        }

        if device.isLocked || device.isAccessRestrictedAppleDevice {
            fputs("warning: ImageCaptureCore reports the device as locked/access-restricted; attempting session open anyway.\n", stderr)
        }

        device.delegate = self
        requestOpenSession(on: device)
        while !isReady && !removed && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))

            if let error = openError {
                if shouldRetryOpenSession(error) {
                    fputs("warning: iPhone still reports locked/access-restricted. Unlock it, keep the screen awake, and approve Trust This Mac if prompted; retrying until timeout.\n", stderr)
                    openError = nil
                    Thread.sleep(forTimeInterval: 1.0)
                    requestOpenSession(on: device)
                    continue
                }
                break
            }
        }

        if let openError {
            throw CLIError.openFailed("Could not open ImageCaptureCore session: \(openError)")
        }
        if removed {
            throw CLIError.noDevice
        }
        guard isReady else {
            throw CLIError.timeout("Timed out waiting for iPhone media catalog.")
        }

        let cameraFiles = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        let mapped = cameraFiles.enumerated().map { index, file in
            (makeDeviceMediaFile(file, fallbackIndex: index), file)
        }
        return (device, mapped)
    }

    func delete(_ files: [ICCameraFile], from device: ICCameraDevice) throws -> DeleteSummary {
        guard options.delete, options.confirmedDeviceDelete else {
            throw CLIError.deleteNotConfirmed
        }
        guard #available(macOS 10.15, *) else {
            device.requestDeleteFiles(files)
            return DeleteSummary(successful: files, failed: [], canceled: [], error: nil)
        }

        var done = false
        var summary = DeleteSummary(successful: [], failed: [], canceled: [], error: nil)
        _ = device.requestDeleteFiles(files, deleteFailed: { failures in
            summary.failed.append(contentsOf: failures.values.compactMap { $0 as? ICCameraFile })
        }, completion: { result, error in
            let successful = result[.successful] ?? []
            let failed = result[.failed] ?? []
            let canceled = result[.canceled] ?? []
            summary.successful = successful.compactMap { $0 as? ICCameraFile }
            summary.failed.append(contentsOf: failed.compactMap { $0 as? ICCameraFile })
            summary.canceled = canceled.compactMap { $0 as? ICCameraFile }
            summary.error = error
            done = true
        })

        let deadline = Date().addingTimeInterval(options.timeoutSeconds)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        guard done else {
            throw CLIError.timeout("Timed out waiting for delete completion.")
        }
        return summary
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard selectedDevice == nil, let camera = device as? ICCameraDevice else {
            return
        }
        if let needle = options.deviceNameContains?.lowercased(),
           !(camera.name ?? "").lowercased().contains(needle) {
            return
        }
        selectedDevice = camera
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if selectedDevice === device {
            removed = true
        }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        openError = error
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    func didRemove(_ device: ICDevice) {
        if selectedDevice === device {
            removed = true
        }
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        isReady = true
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    private func requestOpenSession(on device: ICCameraDevice) {
        openError = nil
        device.requestOpenSession()
    }

    private func shouldRetryOpenSession(_ error: Error) -> Bool {
        let nsError = error as NSError
        return OpenSessionRetry.shouldRetry(
            domain: nsError.domain,
            code: nsError.code,
            description: nsError.localizedDescription
        )
    }
}

struct DeleteSummary {
    var successful: [ICCameraFile]
    var failed: [ICCameraFile]
    var canceled: [ICCameraFile]
    var error: Error?
}

@main
struct IPhoneDedupe {
    static func main() {
        do {
            let options = try parseOptions(CommandLine.arguments)
            let scanner = CameraScanner(options: options)
            let scan = try scanner.scan()
            let plan = DuplicatePlanner.plan(files: scan.files.map(\.0), rule: options.rule)
            let deleteIDs = Set(plan.delete.map(\.id))
            let filesToDelete = scan.files.filter { deleteIDs.contains($0.0.id) }
            let csvURL = URL(fileURLWithPath: options.csvPath ?? defaultCSVPath())
            try writeCSV(scan.files.map(\.0), plan: plan, to: csvURL)

            print("Device: \(scan.device.name ?? "unknown")")
            print("Files scanned: \(scan.files.count)")
            print("Rule: \(options.rule.rawValue)")
            print("Duplicates planned for deletion: \(filesToDelete.count)")
            print("CSV: \(csvURL.path)")

            if options.delete {
                if DeleteRequestPolicy.shouldCallDeviceDelete(plannedDeleteCount: filesToDelete.count) {
                    let summary = try scanner.delete(filesToDelete.map(\.1), from: scan.device)
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

private func makeDeviceMediaFile(_ file: ICCameraFile, fallbackIndex: Int) -> DeviceMediaFile {
    let name = file.name ?? file.originalFilename ?? "unknown-\(fallbackIndex)"
    return DeviceMediaFile(
        id: "\(file.ptpObjectHandle)-\(fallbackIndex)-\(name)",
        name: name,
        kind: kind(for: file, name: name),
        size: Int64(file.fileSize),
        timestamp: timestamp(for: file),
        width: file.width > 0 ? file.width : nil,
        height: file.height > 0 ? file.height : nil
    )
}

private func kind(for file: ICCameraFile, name: String) -> String {
    if let ext = name.split(separator: ".").last, ext != name {
        return ext.uppercased()
    }
    return file.uti?.uppercased() ?? "UNKNOWN"
}

private func timestamp(for file: ICCameraFile) -> String? {
    let date = file.exifCreationDate ?? file.fileCreationDate ?? file.creationDate ?? file.fileModificationDate ?? file.modificationDate
    guard let date else {
        return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
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
