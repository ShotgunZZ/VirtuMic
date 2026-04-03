import SwiftUI

struct MixerView: View {
    @ObservedObject var engine: AudioEngine

    var body: some View {
        VStack {
            Text("VirtuMic Mixer")
                .font(.headline)
            Text(engine.isRunning ? "Engine Running" : "Engine Stopped")
        }
        .frame(width: 360, height: 520)
    }
}
