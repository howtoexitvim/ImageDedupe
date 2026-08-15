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
