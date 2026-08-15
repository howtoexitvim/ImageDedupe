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
    /// Seconds `double-scan` waits between its two scans, so a photo can be added or
    /// removed on the device in between. Without a mutation the two scans are identical
    /// whether or not the second one actually re-enumerated, which is what made the
    /// staleness question unanswerable from counts alone.
    let pauseSeconds: TimeInterval

    static func parse(_ raw: [String]) throws -> Arguments {
        guard let command = raw.first else {
            throw CommandError.missingCommand
        }

        var targetName: String?
        var timeout: TimeInterval = 180
        var destination: URL?
        var delete = false
        var confirmed = false
        var pauseSeconds: TimeInterval = 0
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
            case "--pause-seconds":
                guard index + 1 < raw.count else {
                    throw CommandError.missingValue(arg)
                }
                pauseSeconds = TimeInterval(raw[index + 1]) ?? pauseSeconds
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
            confirmed: confirmed,
            pauseSeconds: pauseSeconds
        )
    }
}

private func printUsage() {
    print("""
    Usage:
      ImageDedupeVerifier scan [--timeout 180]
      ImageDedupeVerifier find-exact-name --target-name CJKU9084.PNG [--timeout 180]
      ImageDedupeVerifier inspect-location --target-name IMG_1309.HEIC [--timeout 180]
      ImageDedupeVerifier import-exact-name --target-name IMG_1128.HEIC --destination /tmp [--timeout 180]
      ImageDedupeVerifier delete-exact-name --target-name CJKU9084.PNG --delete --i-understand-this-deletes-from-device [--timeout 180]
    """)
}

@MainActor
/// Scans, retrying only transient failures.
///
/// `attempts` defaults to 1 because retrying multiplies a wait the user already experiences
/// as a hang: with a locked iPhone and a 180-second timeout this turned one stall into 559
/// seconds. The app itself scans once and lets the user press Scan again, which is both
/// faster to fail and clearer about why.
private func scanWithRetry(
    gateway: ImageCaptureDeviceGateway,
    timeout: TimeInterval,
    attempts: Int = 1,
    delaySeconds: TimeInterval = 3
) async throws -> DeviceCatalogSnapshot {
    var lastError: Error?
    for attempt in 1...attempts {
        do {
            return try await gateway.scan(timeout: .seconds(timeout))
        } catch {
            lastError = error
            if attempt < attempts {
                fputs("warning: scan attempt \(attempt) failed: \(error). Retrying...\n", stderr)
                try await Task.sleep(for: .seconds(delaySeconds))
            }
        }
    }
    throw lastError ?? DeviceMediaError.noDevice
}

@MainActor
private func runDoubleScan(timeout: TimeInterval, pauseSeconds: TimeInterval) async throws {
    let gateway = ImageCaptureDeviceGateway()
    let firstStart = Date()
    let first = try await gateway.scan(timeout: .seconds(timeout))
    print("firstScan=\(first.files.count) seconds=\(String(format: "%.2f", Date().timeIntervalSince(firstStart)))")

    if pauseSeconds > 0 {
        // Equal counts prove nothing on their own, so the operator is given a window to
        // change the device. The set difference below is the actual evidence.
        print("pausing=\(Int(pauseSeconds))s — add or delete a photo on the iPhone now")
        try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000))
    }

    let secondStart = Date()
    do {
        let second = try await gateway.scan(timeout: .seconds(timeout))
        print("secondScan=\(second.files.count) seconds=\(String(format: "%.2f", Date().timeIntervalSince(secondStart)))")

        let before = Set(first.files.map(\.model.name))
        let after = Set(second.files.map(\.model.name))
        let added = after.subtracting(before).sorted()
        let removed = before.subtracting(after).sorted()
        print("added=\(added.count) removed=\(removed.count)")
        for name in added.prefix(10) { print("  +\(name)") }
        for name in removed.prefix(10) { print("  -\(name)") }
        // The bottom line: did the second scan observe the device as it is now?
        print("secondScanSawDeviceChanges=\(!added.isEmpty || !removed.isEmpty)")
    } catch {
        print("secondScanFailed=\(error) seconds=\(String(format: "%.2f", Date().timeIntervalSince(secondStart)))")
    }
}

@MainActor
private func runScan(timeout: TimeInterval) async throws {
    let gateway = ImageCaptureDeviceGateway()
    let result = try await scanWithRetry(gateway: gateway, timeout: timeout)
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

@MainActor
private func findExactName(_ args: Arguments) async throws {
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }

    let gateway = ImageCaptureDeviceGateway()
    let result = try await scanWithRetry(gateway: gateway, timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }
    print("device=\(result.deviceName)")
    print("scanned=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    for match in matches {
        print("match=\(match.model.name) kind=\(match.model.kind) size=\(match.model.size) timestamp=\(match.model.timestamp ?? "unknown") location=\(match.model.location ?? "unknown")")
    }
}

@MainActor
private func inspectLocation(_ args: Arguments) async throws {
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }

    let gateway = ImageCaptureDeviceGateway()
    let result = try await scanWithRetry(gateway: gateway, timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }
    print("device=\(result.deviceName)")
    print("scanned=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    guard let match = matches.first else {
        return
    }

    print("mapped.location=\(match.model.location ?? "unknown")")
    print("mapped.width=\(match.model.width.map(String.init) ?? "unknown")")
    print("mapped.height=\(match.model.height.map(String.init) ?? "unknown")")
    print("requestingMetadata=true")

    guard let metadata = try await gateway.metadata(for: match.token, timeout: .seconds(30)) else {
        print("metadata=nil")
        return
    }

    print("metadata.location=\(metadata.location ?? "unknown")")
    print("metadata.aperture=\(metadata.aperture ?? "unknown")")
    print("metadata.colorSpace=\(metadata.colorSpace ?? "unknown")")
    print("metadata.shutterSpeed=\(metadata.shutterSpeed ?? "unknown")")
    print("metadata.maker=\(metadata.maker ?? "unknown")")
    print("metadata.model=\(metadata.model ?? "unknown")")
}

@MainActor
private func deleteExactName(_ args: Arguments) async throws {
    guard args.delete, args.confirmed else {
        throw CommandError.deleteNotConfirmed
    }
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }

    let gateway = ImageCaptureDeviceGateway()
    let result = try await scanWithRetry(gateway: gateway, timeout: args.timeout)
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

    let summary = try await gateway.delete(
        matches.map(\.token),
        confirmed: true,
        timeout: .seconds(args.timeout)
    )
    print("deleteSuccessful=\(summary.successful.count)")
    print("deleteFailed=\(summary.failed.count)")
    print("deleteCanceled=\(summary.canceled.count)")

    // Evidence from the device's own removal notification, which the app uses to confirm a
    // delete without rescanning the whole catalog. Reported here so the fast path can be
    // measured against the authoritative rescan below.
    let observed = gateway.observedRemovals
    let provenByCallback = matches.filter { observed.contains($0.token.objectHandle) }
    print("observedRemovalEvidence=\(provenByCallback.count) of \(matches.count)")

    // Deliberately not rescanning on this gateway. ImageCaptureCore delivers a catalog once
    // per device object, so an in-process scan after a delete replays the snapshot taken
    // when the session opened and still lists the file that was just removed — measured
    // reporting `remainingExactMatches=1` for a delete that a fresh process confirmed had
    // worked. Only a new process can answer this, so the tool says so rather than printing
    // a number that looks like evidence and is not.
    print("postDeleteVerification=requires-fresh-process")
    print("verifyWith=ImageDedupeVerifier find-exact-name --target-name \(targetName)")
}

@MainActor
private func importExactName(_ args: Arguments) async throws {
    guard let targetName = args.targetName, !targetName.isEmpty else {
        throw CommandError.missingValue("--target-name")
    }
    guard let destination = args.destination else {
        throw CommandError.missingValue("--destination")
    }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let destinationIdentity = try ImportDestinationIdentity.capture(destination: destination)
    let stagingManager = ImportStagingManager.applicationCaches()
    let stagingSession = try stagingManager.createSession()
    defer { try? stagingManager.cleanup(stagingSession) }
    let gateway = ImageCaptureDeviceGateway()
    let result = try await scanWithRetry(gateway: gateway, timeout: args.timeout)
    let matches = result.files.filter { $0.model.name == targetName }
    print("device=\(result.deviceName)")
    print("scanned=\(result.files.count)")
    print("targetName=\(targetName)")
    print("exactMatches=\(matches.count)")
    guard matches.count == 1 else {
        throw CommandError.unsafeMatchCount(matches.count)
    }

    let summary = await gateway.download(
        matches.map(\.token),
        to: stagingSession,
        timeout: .seconds(args.timeout)
    )
    print("importSuccessful=\(summary.successful.count)")
    print("importFailed=\(summary.failed.count)")
    for imported in summary.successful {
        let output = try DestinationCommitter.commit(
            stagedFilename: imported.filename,
            stagingDirectory: stagingSession.directory,
            stagingIdentity: stagingSession.identity,
            stagedIdentity: imported.stagedIdentity,
            filename: matches[0].model.name,
            destination: destination,
            destinationIdentity: destinationIdentity
        )
        print("imported=\(output.path)")
    }
    for failure in summary.failed {
        print("failure=\(failure.filename) error=\(failure.reason)")
    }
}

do {
    let args = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    switch args.command {
    case "scan":
        try await runScan(timeout: args.timeout)
    case "flow-check":
        await FlowCheck.run(
            timeout: args.timeout,
            destination: args.destination ?? URL(fileURLWithPath: NSTemporaryDirectory()),
            deleteTarget: args.targetName,
            confirmedDelete: args.delete && args.confirmed
        )
    case "session-check":
        await SessionCheck.run(timeout: args.timeout, pauseSeconds: args.pauseSeconds)
    case "double-scan":
        // Diagnostic: isolates whether a second scan on the same gateway completes, with no
        // delete involved. A one-file delete took minutes because its verification rescan
        // never received `deviceDidBecomeReady`, and this separates that from the delete.
        try await runDoubleScan(timeout: args.timeout, pauseSeconds: args.pauseSeconds)
    case "find-exact-name":
        try await findExactName(args)
    case "inspect-location":
        try await inspectLocation(args)
    case "import-exact-name":
        try await importExactName(args)
    case "delete-exact-name":
        try await deleteExactName(args)
    default:
        throw CommandError.unknownCommand(args.command)
    }
} catch {
    fputs("error: \(error)\n", stderr)
    printUsage()
    exit(1)
}
