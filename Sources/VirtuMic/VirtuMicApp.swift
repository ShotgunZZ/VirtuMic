import SwiftUI

@main
struct VirtuMicApp: App {
    var body: some Scene {
        MenuBarExtra("VirtuMic", systemImage: "mic.fill") {
            Text("VirtuMic loading...")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
