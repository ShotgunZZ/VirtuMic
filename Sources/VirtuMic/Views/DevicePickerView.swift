import SwiftUI

struct DevicePickerView: View {
    @ObservedObject var engine: AudioEngine

    @State private var inputDevices: [String] = []
    @State private var outputDevices: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEVICES")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { engine.config.inputDevice },
                        set: { engine.setInputDevice($0) }
                    )) {
                        ForEach(inputDevices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        if !inputDevices.contains(engine.config.inputDevice) {
                            Text("\(engine.config.inputDevice) (not found)")
                                .foregroundColor(.red)
                                .tag(engine.config.inputDevice)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Output")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { engine.config.outputDevice },
                        set: { engine.setOutputDevice($0) }
                    )) {
                        ForEach(outputDevices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        if !outputDevices.contains(engine.config.outputDevice) {
                            Text("\(engine.config.outputDevice) (not found)")
                                .foregroundColor(.red)
                                .tag(engine.config.outputDevice)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .onAppear { refreshDevices() }
    }

    private func refreshDevices() {
        let devices = engine.availableDevices()
        inputDevices = devices.filter { $0.hasInput }.map { $0.name }
        outputDevices = devices.filter { $0.hasOutput }.map { $0.name }
    }
}
