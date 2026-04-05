import SwiftUI

struct CompressorView: View {
    @ObservedObject var engine: AudioEngine

    @State private var threshold: Float = -20
    @State private var headRoom: Float = 5
    @State private var attack: Float = 0.01
    @State private var release: Float = 0.1
    @State private var gain: Float = 0

    var body: some View {
        SectionView(title: "Compressor", enabled: engine.config.compressor.enabled, onToggle: {
            engine.setCompressorEnabled(!engine.config.compressor.enabled)
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    ParameterSlider(label: "Threshold", value: $threshold, range: -40...20, unit: "dB", format: "%.1f") {
                        engine.setCompressorThreshold($0)
                    }
                    ParameterSlider(label: "Headroom", value: $headRoom, range: 0.1...40, unit: "dB", format: "%.1f") {
                        engine.setCompressorHeadroom($0)
                    }
                }
                HStack(spacing: 12) {
                    ParameterSlider(label: "Attack", value: $attack, range: 0.0001...0.2, unit: "s", format: "%.4f", logarithmic: true) {
                        engine.setCompressorAttack($0)
                    }
                    ParameterSlider(label: "Release", value: $release, range: 0.01...3.0, unit: "s", format: "%.2f", logarithmic: true) {
                        engine.setCompressorRelease($0)
                    }
                }
                ParameterSlider(label: "Makeup Gain", value: $gain, range: -40...40, unit: "dB", format: "%.1f") {
                    engine.setCompressorGain($0)
                }
            }
        }
        .onAppear {
            threshold = engine.config.compressor.threshold
            headRoom = engine.config.compressor.headRoom
            attack = engine.config.compressor.attackTime
            release = engine.config.compressor.releaseTime
            gain = engine.config.compressor.masterGain
        }
    }
}
