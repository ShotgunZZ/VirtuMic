import SwiftUI

@main
struct VirtuMicApp: App {
    @StateObject private var engine = AudioEngine()
    @State private var windowController: MixerWindowController?

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                if engine.isRunning {
                    Text("Status: Running")
                        .foregroundColor(.green)
                } else if let error = engine.errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                } else {
                    Text("Status: Stopped")
                        .foregroundColor(.gray)
                }

                Divider()

                Button(engine.isRunning ? "Stop Engine" : "Start Engine") {
                    engine.toggle()
                }

                Button("Show Mixer") {
                    ensureWindowController()
                    windowController?.toggle()
                }
                .keyboardShortcut("m")

                Divider()

                Button("Quit VirtuMic") {
                    engine.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(4)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                if !engine.isRunning {
                    engine.start()
                }
            }
        } label: {
            Image(systemName: engine.isRunning ? "mic.fill" : "mic.slash.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(engine.isRunning ? .green : .gray)
        }
    }

    private func ensureWindowController() {
        if windowController == nil {
            windowController = MixerWindowController(engine: engine)
        }
    }
}
