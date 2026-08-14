import SwiftUI

@main
struct IPhoneDedupeMacApp: App {
    var body: some Scene {
        WindowGroup("iPhone Dedupe") {
            MediaBrowserView(autoScanOnLaunch: CommandLine.arguments.contains("--auto-scan"))
                .frame(width: 1280, height: 760)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
