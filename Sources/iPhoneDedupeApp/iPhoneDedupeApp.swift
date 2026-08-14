import SwiftUI

@main
struct IPhoneDedupeMacApp: App {
    var body: some Scene {
        WindowGroup("iPhone Dedupe") {
            MediaBrowserView(autoScanOnLaunch: CommandLine.arguments.contains("--auto-scan"))
                .frame(minWidth: 940, idealWidth: 1280, minHeight: 760, idealHeight: 760)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
