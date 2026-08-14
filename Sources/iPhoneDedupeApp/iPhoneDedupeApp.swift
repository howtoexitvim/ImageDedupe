import SwiftUI

@main
struct IPhoneDedupeMacApp: App {
    var body: some Scene {
        WindowGroup("iPhone Dedupe") {
            MediaBrowserView()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
