import DeduperCore
import DeviceMediaKit
import Foundation

/// Diagnostic: proves `DeviceSession` can rescan, which the in-process gateway cannot.
enum SessionCheck {
    static func run(timeout: TimeInterval, pauseSeconds: TimeInterval) async {
        let helper = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("ImageDedupeHelper")
        let session = DeviceSession(makeClient: { DeviceHelperClient(executableURL: helper) })

        do {
            let first = try await session.scan(timeout: .seconds(timeout))
            print("sessionScan1=\(first.files.count)")

            // The crash on 2026-08-15 was Dictionary(uniqueKeysWithValues:) trapping on a
            // duplicate model id, so report collisions directly.
            var seen: [String: Int] = [:]
            for file in first.files { seen[file.model.id, default: 0] += 1 }
            let collisions = seen.filter { $0.value > 1 }
            print("duplicateModelIDs=\(collisions.count)")

            // Do a group's copies ever differ in size? If not, "keep the largest" is a
            // coin flip dressed up as a policy.
            let groups = DuplicateGrouping.groups(
                files: first.files.map(\.model),
                definition: DuplicateRuleSelection.default.definition
            )
            var differingSizes = 0
            for group in groups where Set(group.members.map(\.file.size)).count > 1 {
                differingSizes += 1
            }
            print("duplicateGroups=\(groups.count) groupsWithDifferingSizes=\(differingSizes)")
            for group in groups.prefix(5) {
                let sizes = group.members.map { String($0.file.size) }.joined(separator: ",")
                print("  group=\(group.title) sizes=[\(sizes)]")
            }

            // What each candidate rule would mark for deletion on the real catalog.
            let models = first.files.map(\.model)
            let candidates: [(String, [MediaField])] = [
                ("Name+Kind+Size", [.name, .kind, .size]),
                ("Name+Kind", [.name, .kind]),
                ("Name+Size", [.name, .size]),
                ("Name only", [.name]),
                ("Size only", [.size]),
                ("Date only", [.timestamp]),
                ("Kind+Size", [.kind, .size])
            ]
            for (label, fields) in candidates {
                let definition = DuplicateRuleDefinition(
                    id: label,
                    fields: fields.map { field in
                        switch field {
                        case .name: return RuleField(field: .name, normalizers: [.lowercase])
                        case .kind: return RuleField(field: .kind, normalizers: [.uppercase])
                        default: return RuleField(field: field)
                        }
                    }
                )
                let plan = DuplicatePlanner.plan(files: models, definition: definition)
                print("rule=\(label) wouldDelete=\(plan.delete.count)")
            }
            for (id, count) in collisions.prefix(10) { print("  collision id=\(id) count=\(count)") }

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

            // The app's verification path: a second helper's catalog must no longer list a
            // file deleted through the first. Reported without deleting anything here.
            let firstNames = Set(first.files.map(\.model.name))
            let secondNames = Set(second.files.map(\.model.name))
            print("verificationCatalogIsFresh=\(first.generation != second.generation)")
            print("namesOnlyInFirst=\(firstNames.subtracting(secondNames).count)")

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
