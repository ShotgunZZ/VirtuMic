import SwiftUI

struct MixerView: View {
    @ObservedObject var engine: AudioEngine

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    DevicePickerView(engine: engine)
                    NoiseGateView(engine: engine)
                    EqualizerView(engine: engine)
                    CompressorView(engine: engine)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if !engine.isRunning {
                engine.start()
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Text("VirtuMic")
                .font(.headline)

            Spacer()

            LevelMeterView(level: engine.inputLevel)
                .frame(width: 100)

            Button(action: { engine.toggle() }) {
                Text(engine.isRunning ? "ON" : "OFF")
                    .font(.caption.bold())
                    .foregroundColor(engine.isRunning ? .green : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(engine.isRunning ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
