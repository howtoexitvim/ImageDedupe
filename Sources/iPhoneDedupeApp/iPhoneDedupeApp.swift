import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct IPhoneDedupeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("iPhone Dedupe") {
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
