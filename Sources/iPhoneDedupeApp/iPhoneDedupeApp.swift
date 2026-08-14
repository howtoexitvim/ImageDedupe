import SwiftUI

@main
struct IPhoneDedupeMacApp: App {
    var body: some Scene {
        WindowGroup("iPhone Dedupe") {
            MediaBrowserView()
                .frame(minWidth: 1180, minHeight: 740)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
