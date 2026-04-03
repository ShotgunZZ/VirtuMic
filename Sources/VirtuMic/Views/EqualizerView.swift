import SwiftUI
import AVFoundation

struct EqualizerView: View {
    @ObservedObject var engine: AudioEngine
    @State private var selectedBand: Int? = nil
    @State private var bandStates: [BandState] = []

    struct BandState {
        var filterType: AVAudioUnitEQFilterType
        var frequency: Float
        var gain: Float
        var bandwidth: Float
    }

    private let bandColors: [Color] = [.purple, .pink, .green, .yellow, .cyan, .orange, .blue, .red]

    private let filterTypeOptions: [(String, AVAudioUnitEQFilterType)] = [
        ("High Pass", .highPass),
        ("Low Pass", .lowPass),
        ("Parametric", .parametric),
        ("Low Shelf", .lowShelf),
        ("High Shelf", .highShelf),
        ("Band Pass", .bandPass),
        ("Band Stop", .bandStop),
    ]

    var body: some View {
        SectionView(title: "Equalizer", enabled: engine.config.eq.enabled, onToggle: {
            engine.setEQEnabled(!engine.config.eq.enabled)
        }) {
            VStack(spacing: 8) {
                EQCurveView(
                    bands: engine.config.eq.bands,
                    sampleRate: engine.config.sampleRate,
                    selectedBand: selectedBand
                )

                HStack(spacing: 4) {
                    ForEach(0..<bandStates.count, id: \.self) { i in
                        bandCard(index: i)
                    }
                }

                if let sel = selectedBand, sel < bandStates.count {
                    bandEditor(index: sel)
                }

                ParameterSlider(
                    label: "Global Gain",
                    value: Binding(
                        get: { engine.config.eq.globalGain },
                        set: { engine.setEQGlobalGain($0) }
                    ),
                    range: -24...24,
                    unit: "dB",
                    format: "%.1f"
                )
            }
        }
        .onAppear { syncFromConfig() }
    }

    private func bandCard(index: Int) -> some View {
        let band = bandStates[index]
        let color = bandColors[index % bandColors.count]
        let isSelected = selectedBand == index

        return Button(action: {
            selectedBand = selectedBand == index ? nil : index
        }) {
            VStack(spacing: 2) {
                Text(shortFilterName(band.filterType))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color)
                Text(formatFreq(band.frequency))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Text(String(format: "%.0f dB", band.gain))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.white.opacity(isSelected ? 0.1 : 0.03))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: isSelected ? 2 : 0)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(color).frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func bandEditor(index: Int) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { bandStates[index].filterType },
                    set: { newType in
                        bandStates[index].filterType = newType
                        applyBand(index)
                    }
                )) {
                    ForEach(filterTypeOptions, id: \.1) { name, type in
                        Text(name).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            ParameterSlider(
                label: "Frequency",
                value: $bandStates[index].frequency,
                range: 20...20000,
                unit: "Hz",
                format: "%.0f",
                logarithmic: true
            ) { _ in applyBand(index) }

            ParameterSlider(
                label: "Gain",
                value: $bandStates[index].gain,
                range: -24...24,
                unit: "dB",
                format: "%.1f"
            ) { _ in applyBand(index) }

            ParameterSlider(
                label: "Bandwidth",
                value: $bandStates[index].bandwidth,
                range: 0.05...5.0,
                unit: "oct",
                format: "%.2f"
            ) { _ in applyBand(index) }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }

    private func applyBand(_ index: Int) {
        let s = bandStates[index]
        engine.setEQBand(index: index, filterType: s.filterType, frequency: s.frequency, gain: s.gain, bandwidth: s.bandwidth)
    }

    private func syncFromConfig() {
        bandStates = engine.config.eq.bands.map { band in
            BandState(
                filterType: AudioConfig.filterType(from: band.filterType),
                frequency: band.frequency,
                gain: band.gain,
                bandwidth: band.bandwidth
            )
        }
    }

    private func shortFilterName(_ type: AVAudioUnitEQFilterType) -> String {
        switch type {
        case .highPass: return "HP"
        case .lowPass: return "LP"
        case .parametric: return "PARA"
        case .lowShelf: return "LS"
        case .highShelf: return "HS"
        case .bandPass: return "BP"
        case .bandStop: return "BS"
        default: return "?"
        }
    }

    private func formatFreq(_ freq: Float) -> String {
        if freq >= 1000 { return String(format: "%.1fk", freq / 1000) }
        return String(format: "%.0f", freq)
    }
}
