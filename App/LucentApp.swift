import SwiftUI

@main
struct LucentApp: App {
    var body: some Scene {
        MenuBarExtra("Lucent", systemImage: "eye") {
            Text("Lucent v0.1.0")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
