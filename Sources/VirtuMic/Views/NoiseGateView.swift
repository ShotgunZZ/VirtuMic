import SwiftUI

struct NoiseGateView: View {
    @ObservedObject var engine: AudioEngine

    @State private var threshold: Float = -40
    @State private var attack: Float = 0.002
    @State private var release: Float = 0.05
    @State private var hold: Float = 0.1

    var body: some View {
        SectionView(title: "Noise Gate", enabled: engine.config.noiseGate.enabled, onToggle: {
            engine.setNoiseGateEnabled(!engine.config.noiseGate.enabled)
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    ParameterSlider(label: "Threshold", value: $threshold, range: -96...0, unit: "dB", format: "%.1f") {
                        engine.setNoiseGateThreshold($0)
                    }
                    ParameterSlider(label: "Attack", value: $attack, range: 0.0001...0.1, unit: "s", format: "%.4f", logarithmic: true) {
                        engine.setNoiseGateAttack($0)
                    }
                }
                HStack(spacing: 12) {
                    ParameterSlider(label: "Release", value: $release, range: 0.01...1.0, unit: "s", format: "%.2f", logarithmic: true) {
                        engine.setNoiseGateRelease($0)
                    }
                    ParameterSlider(label: "Hold", value: $hold, range: 0...2.0, unit: "s", format: "%.2f") {
                        engine.setNoiseGateHold($0)
                    }
                }
            }
        }
        .onAppear {
            threshold = engine.config.noiseGate.thresholdDB
            attack = engine.config.noiseGate.attackTime
            release = engine.config.noiseGate.releaseTime
            hold = engine.config.noiseGate.holdTime
        }
    }
}

struct SectionView<Content: View>: View {
    let title: String
    let enabled: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onToggle) {
                    Text(enabled ? "ON" : "OFF")
                        .font(.caption2.bold())
                        .foregroundColor(enabled ? .green : .gray)
                }
                .buttonStyle(.plain)
            }

            content()
                .opacity(enabled ? 1.0 : 0.4)
                .disabled(!enabled)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}
