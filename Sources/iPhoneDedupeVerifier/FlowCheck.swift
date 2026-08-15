import DeduperCore
import DeviceMediaKit
import Foundation

/// Walks the device flows end to end through `DeviceSession`, the same path the app uses.
///
/// This exists because the flows only break in combination: a cancel that poisons the next
/// command, a download whose reply is claimed by a thumbnail, a delete whose verification
/// reads a stale catalog. Each individual command had been spot-checked and still the
/// combination failed, so the combinations are what this runs.
///
/// It never deletes anything on its own. Deleting requires `--delete` plus an explicit
/// `--target-name`, so a flow run cannot become destructive by accident.
@MainActor
enum FlowCheck {
    private static func helperURL() -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("iPhoneDedupeHelper")
    }

    private static func makeSession() -> DeviceSession {
        let helper = helperURL()
        return DeviceSession(makeClient: { DeviceHelperClient(executableURL: helper) })
    }

    private static var failures: [String] = []

    private static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        let mark = condition ? "PASS" : "FAIL"
        print("  [\(mark)] \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !condition { failures.append(label) }
    }

    static func run(
        timeout: TimeInterval,
        destination: URL,
        deleteTarget: String?,
        confirmedDelete: Bool
    ) async {
        failures = []
        print("=== Flow check: destination=\(destination.path) ===")

        await scanDownloadScan(timeout: timeout, destination: destination)
        await downloadCancelThenStillWorks(timeout: timeout, destination: destination)
        await deleteCancelThenStillWorks(timeout: timeout)
        await sequenceStress(timeout: timeout, destination: destination)

        if let deleteTarget, confirmedDelete {
            await deleteFlow(timeout: timeout, destination: destination, targetName: deleteTarget)
        } else {
            print("\n-- delete flow skipped (needs --target-name and the delete flags) --")
        }

        print("\n=== \(failures.isEmpty ? "ALL FLOWS PASSED" : "FAILURES: \(failures.joined(separator: ", "))") ===")
    }

    // MARK: - Download, scan, download

    private static func scanDownloadScan(timeout: TimeInterval, destination: URL) async {
        print("\n-- scan → download → scan → download (badge consistency) --")
        let session = makeSession()
        defer { Task { await session.retire() } }

        guard let first = try? await session.scan(timeout: .seconds(timeout)),
              let target = first.files.first(where: { $0.model.size < 5_000_000 }) else {
            check("initial scan", false, "no scan or no small file")
            return
        }
        check("initial scan", true, "\(first.files.count) files")

        let name = target.model.name
        let landed = destination.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: landed)

        guard let summary = await downloadOne(session: session, token: target.token, destination: destination, timeout: timeout) else {
            check("download completes", false)
            return
        }
        check("download completes", summary.failed.isEmpty, "\(summary.successful.count) ok, \(summary.failed.count) failed")
        check("downloaded file is on disk", FileManager.default.fileExists(atPath: landed.path), landed.lastPathComponent)

        // A second scan must still work after a download, and must still see the file.
        guard let second = try? await session.scan(timeout: .seconds(timeout)) else {
            check("scan after download", false)
            return
        }
        check("scan after download", true, "\(second.files.count) files")
        check(
            "downloaded file survives the rescan on disk",
            FileManager.default.fileExists(atPath: landed.path),
            "this is what the badge is derived from"
        )
        check("rescan produces a new generation", first.generation != second.generation)
    }

    // MARK: - Download cancel

    private static func downloadCancelThenStillWorks(timeout: TimeInterval, destination: URL) async {
        print("\n-- download → cancel → previews/download/scan still work --")
        let session = makeSession()
        defer { Task { await session.retire() } }

        guard let catalog = try? await session.scan(timeout: .seconds(timeout)) else {
            check("scan before cancel", false)
            return
        }
        check("scan before cancel", true, "\(catalog.files.count) files")

        // A large batch, so there is something in flight to cancel.
        let batch = Array(catalog.files.prefix(25)).map(\.token)
        let staging = ImportStagingManager.applicationCaches()
        guard let stagingSession = try? staging.createSession() else {
            check("staging session", false)
            return
        }
        defer { try? staging.cleanup(stagingSession) }

        async let result: DeviceGatewayImportSummary? = try? await session.download(
            batch,
            stagingDirectory: stagingSession.directory,
            timeout: .seconds(timeout)
        )
        try? await Task.sleep(for: .milliseconds(400))
        await session.cancel()
        let summary = await result
        check("canceled download settles", summary != nil, "did not hang")

        // The latches that used to break every later command after one cancel.
        let previewWorks = (try? await session.thumbnailData(
            for: catalog.files[0].token,
            maxPixelSize: 128,
            timeout: .seconds(30)
        )) != nil
        check("preview works after a download cancel", previewWorks)

        let secondDownload = await downloadOne(
            session: session,
            token: catalog.files[1].token,
            destination: destination,
            timeout: timeout
        )
        check("download works after a download cancel", secondDownload?.failed.isEmpty == true)

        let rescan = try? await session.scan(timeout: .seconds(timeout))
        check("scan works after a download cancel", rescan != nil, "\(rescan?.files.count ?? -1) files")
    }

    // MARK: - Delete cancel

    private static func deleteCancelThenStillWorks(timeout: TimeInterval) async {
        print("\n-- delete cancel (canceled before submission) → previews/scan still work --")
        let session = makeSession()
        defer { Task { await session.retire() } }

        guard let catalog = try? await session.scan(timeout: .seconds(timeout)) else {
            check("scan before delete cancel", false)
            return
        }

        // Deliberately submitted **unconfirmed**, so the gateway rejects it before any
        // framework delete is issued. A racing cancel that lost the race would otherwise
        // delete a real photo that nobody approved, and no test is worth that. This still
        // exercises the path that matters here: whether a rejected/canceled delete leaves
        // the gateway usable, which is where the one-way latches used to bite.
        let token = catalog.files[0].token
        async let result: (summary: DeviceGatewayDeleteSummary, observedRemovedHandles: Set<UInt32>)? =
            try? await session.delete([token], confirmed: false, timeout: .seconds(timeout))
        await session.cancel()
        let outcome = await result
        check(
            "unconfirmed delete is refused rather than performed",
            outcome == nil,
            "no framework delete was issued"
        )

        let previewWorks = (try? await session.thumbnailData(
            for: catalog.files[0].token,
            maxPixelSize: 128,
            timeout: .seconds(30)
        )) != nil
        check("preview works after a delete cancel", previewWorks)

        let rescan = try? await session.scan(timeout: .seconds(timeout))
        check("scan works after a delete cancel", rescan != nil, "\(rescan?.files.count ?? -1) files")
    }

    /// The interleavings the user asked for, in one long-lived session.
    ///
    /// Individually each command already worked; what kept breaking was the *combination*,
    /// because one canceled operation used to latch the gateway and every later command
    /// failed. Running them back to back in one session is what would catch that.
    private static func sequenceStress(timeout: TimeInterval, destination: URL) async {
        print("\n-- download → cancel → scan → download → cancel → scan (one session) --")
        let session = makeSession()
        defer { Task { await session.retire() } }

        guard var catalog = try? await session.scan(timeout: .seconds(timeout)) else {
            check("sequence: first scan", false)
            return
        }
        check("sequence: first scan", true, "\(catalog.files.count) files")

        for round in 1...2 {
            let staging = ImportStagingManager.applicationCaches()
            guard let stagingSession = try? staging.createSession() else { continue }
            let batch = Array(catalog.files.prefix(20)).map(\.token)

            async let running: DeviceGatewayImportSummary? = try? await session.download(
                batch,
                stagingDirectory: stagingSession.directory,
                timeout: .seconds(timeout)
            )
            try? await Task.sleep(for: .milliseconds(350))
            await session.cancel()
            let summary = await running
            try? staging.cleanup(stagingSession)
            check("sequence \(round): canceled download settles", summary != nil)

            guard let rescan = try? await session.scan(timeout: .seconds(timeout)) else {
                check("sequence \(round): scan after cancel", false)
                return
            }
            check("sequence \(round): scan after cancel", true, "\(rescan.files.count) files")
            catalog = rescan

            let single = await downloadOne(
                session: session,
                token: catalog.files[round].token,
                destination: destination,
                timeout: timeout
            )
            check("sequence \(round): download after cancel+scan", single?.failed.isEmpty == true)

            let preview = (try? await session.thumbnailData(
                for: catalog.files[0].token,
                maxPixelSize: 128,
                timeout: .seconds(30)
            )) != nil
            check("sequence \(round): preview after cancel+scan", preview)
        }
    }

    // MARK: - Delete

    private static func deleteFlow(timeout: TimeInterval, destination: URL, targetName: String) async {
        print("\n-- backup → verify backup → delete → verify gone (fresh process) --")
        let session = makeSession()

        guard let catalog = try? await session.scan(timeout: .seconds(timeout)) else {
            check("scan before delete", false)
            await session.retire()
            return
        }
        let matches = catalog.files.filter { $0.model.name == targetName }
        guard matches.count == 1, let target = matches.first else {
            check("exactly one match for \(targetName)", false, "found \(matches.count)")
            await session.retire()
            return
        }

        // Back up first, and confirm the bytes, before anything destructive.
        guard let summary = await downloadOne(session: session, token: target.token, destination: destination, timeout: timeout),
              summary.failed.isEmpty else {
            check("backup downloaded", false)
            await session.retire()
            return
        }
        let backup = destination.appendingPathComponent(targetName)
        let backupSize = (try? FileManager.default.attributesOfItem(atPath: backup.path)[.size] as? Int64) ?? nil
        check("backup exists", FileManager.default.fileExists(atPath: backup.path), backup.path)
        check(
            "backup byte size matches the device",
            backupSize == target.model.size,
            "backup=\(backupSize.map(String.init) ?? "nil") device=\(target.model.size)"
        )
        guard backupSize == target.model.size else {
            print("  refusing to delete: the backup does not match the device")
            await session.retire()
            return
        }

        guard let (deleteSummary, handles) = try? await session.delete(
            [target.token],
            confirmed: true,
            timeout: .seconds(timeout)
        ) else {
            check("delete completes", false)
            await session.retire()
            return
        }
        check("delete reports success", deleteSummary.failed.isEmpty, "\(deleteSummary.successful.count) removed")
        print("  observedRemovalEvidence=\(handles.count)")

        // The app verifies in a new helper; this retires the old one to do the same.
        await session.retire()
        let fresh = makeSession()
        defer { Task { await fresh.retire() } }
        guard let after = try? await fresh.scan(timeout: .seconds(timeout)) else {
            check("verification scan", false)
            return
        }
        let remaining = after.files.filter { $0.model.name == targetName }
        check("file is gone from a fresh catalog", remaining.isEmpty, "remaining=\(remaining.count)")
        check("catalog shrank by one", after.files.count == catalog.files.count - 1,
              "\(catalog.files.count) → \(after.files.count)")
        check("backup survives the delete", FileManager.default.fileExists(atPath: backup.path))
    }

    // MARK: - Helpers

    private static func downloadOne(
        session: DeviceSession,
        token: DeviceFileToken,
        destination: URL,
        timeout: TimeInterval
    ) async -> DeviceGatewayImportSummary? {
        let staging = ImportStagingManager.applicationCaches()
        guard let stagingSession = try? staging.createSession() else { return nil }
        defer { try? staging.cleanup(stagingSession) }

        guard let summary = try? await session.download(
            [token],
            stagingDirectory: stagingSession.directory,
            timeout: .seconds(timeout)
        ) else { return nil }

        // Commit exactly as the app does, so the destination ends up in the same state.
        let destinationIdentity = try? ImportDestinationIdentity.capture(destination: destination)
        for download in summary.successful {
            guard let destinationIdentity else { continue }
            _ = try? DestinationCommitter.commit(
                stagedFilename: download.filename,
                stagingDirectory: stagingSession.directory,
                stagingIdentity: stagingSession.identity,
                stagedIdentity: download.stagedIdentity,
                filename: download.filename,
                destination: destination,
                destinationIdentity: destinationIdentity
            )
        }
        return summary
    }
}
