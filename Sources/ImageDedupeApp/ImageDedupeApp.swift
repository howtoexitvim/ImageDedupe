import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any view reads a setting: renaming the app changed the bundle identifier,
        // and so the `UserDefaults` domain. Without this the duplicate rule, column layout,
        // sort, and pane widths would all silently revert on the first launch afterwards.
        PreferenceMigration.migrateIfNeeded()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ImageDedupeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Image Dedupe") {
            MediaBrowserView(autoScanOnLaunch: CommandLine.arguments.contains("--auto-scan"))
                .frame(
                    minWidth: MediaPaneLayout.minimumWindowWidth,
                    idealWidth: 1280,
                    minHeight: MediaPaneLayout.minimumWindowHeight,
                    idealHeight: 760
                )
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Reset Layout") {
                    NotificationCenter.default.post(name: .mediaResetLayout, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
    }
}
