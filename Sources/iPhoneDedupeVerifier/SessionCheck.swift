import DeviceMediaKit
import Foundation

/// Diagnostic: proves `DeviceSession` can rescan, which the in-process gateway cannot.
enum SessionCheck {
    static func run(timeout: TimeInterval, pauseSeconds: TimeInterval) async {
        let helper = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("iPhoneDedupeHelper")
        let session = DeviceSession(makeClient: { DeviceHelperClient(executableURL: helper) })

        do {
            let first = try await session.scan(timeout: .seconds(timeout))
            print("sessionScan1=\(first.files.count)")

            if pauseSeconds > 0 {
                print("pausing=\(Int(pauseSeconds))s — change the device now")
                try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000))
            }

            // Concurrency check: many thumbnails in flight at once, which is what the app
            // does for a screen of tiles. Each reply must come back to the request that
            // asked, or a tile shows another tile's picture.
            let sample = Array(first.files.prefix(8))
            var mismatches = 0
            await withTaskGroup(of: Bool.self) { group in
                for file in sample {
                    group.addTask {
                        guard let data = try? await session.thumbnailData(
                            for: file.token,
                            maxPixelSize: 128,
                            timeout: .seconds(30)
                        ) else { return false }
                        return !data.isEmpty
                    }
                }
                for await ok in group where !ok { mismatches += 1 }
            }
            print("concurrentThumbnails=\(sample.count) failures=\(mismatches)")

            // Download through the helper, alongside concurrent thumbnails, which is the
            // combination that produced "the device helper sent an unexpected response".
            let staging = ImportStagingManager.applicationCaches()
            if let stagingSession = try? staging.createSession(), let target = first.files.first {
                async let noise: Void = {
                    for file in first.files.prefix(4) {
                        _ = try? await session.thumbnailData(
                            for: file.token,
                            maxPixelSize: 128,
                            timeout: .seconds(30)
                        )
                    }
                }()
                let summary = try? await session.download(
                    [target.token],
                    stagingDirectory: stagingSession.directory,
                    timeout: .seconds(90)
                )
                await noise
                print("helperDownloadSucceeded=\(summary?.successful.count ?? -1) failed=\(summary?.failed.count ?? -1)")
                for failure in summary?.failed ?? [] { print("  downloadFailure=\(failure.reason)") }
                try? staging.cleanup(stagingSession)
            }

            let second = try await session.scan(timeout: .seconds(timeout))
            print("sessionScan2=\(second.files.count)")

            let before = Set(first.files.map(\.model.name))
            let after = Set(second.files.map(\.model.name))
            print("added=\(after.subtracting(before).count) removed=\(before.subtracting(after).count)")
            print("generationsDiffer=\(first.generation != second.generation)")
            await session.retire()
        } catch {
            print("sessionCheckFailed=\(error)")
            await session.retire()
        }
    }
}
