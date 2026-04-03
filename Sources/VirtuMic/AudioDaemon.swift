import AVFoundation
import CoreAudio
import AudioToolbox

final class AudioDaemon {
    private let config: AudioConfig
    private let engine = AVAudioEngine()
    private var aggregateDeviceID: AudioDeviceID = 0

    init(config: AudioConfig) {
        self.config = config
    }

    func start() throws {
        // 1. Find devices
        print("Looking for input device: '\(config.inputDevice)'...")
        let inputDevice = try DeviceManager.findDevice(matching: config.inputDevice, needsInput: true, needsOutput: false)
        print("  Found: \(inputDevice.name) (UID: \(inputDevice.uid))")

        print("Looking for output device: '\(config.outputDevice)'...")
        let outputDevice = try DeviceManager.findDevice(matching: config.outputDevice, needsInput: false, needsOutput: true)
        print("  Found: \(outputDevice.name) (UID: \(outputDevice.uid))")

        // 2. Create aggregate device
        print("Creating aggregate device...")
        aggregateDeviceID = try DeviceManager.createAggregateDevice(
            inputUID: inputDevice.uid,
            outputUID: outputDevice.uid
        )
        print("  Aggregate device created (ID: \(aggregateDeviceID))")

        // 3. Assign aggregate device to engine
        try setEngineDevice(aggregateDeviceID)

        // 4. Get the input format from the engine
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat)")

        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw AudioDaemonError.invalidFormat(description: "Input node has invalid format: \(inputFormat)")
        }

        // 5. Build processing chain
        var lastNode: AVAudioNode = inputNode
        let lastFormat = inputFormat

        // Noise Gate
        if config.noiseGate.enabled {
            print("Attaching noise gate...")
            if let gateNode = makeNoiseGateNode(
                config: config.noiseGate,
                sampleRate: Float(inputFormat.sampleRate)
            ) {
                engine.attach(gateNode)
                engine.connect(lastNode, to: gateNode, format: lastFormat)
                lastNode = gateNode
            } else {
                print("  Warning: Failed to create noise gate node, skipping")
            }
        }

        // EQ
        if config.eq.enabled && !config.eq.bands.isEmpty {
            print("Attaching EQ with \(config.eq.bands.count) bands...")
            let eq = AVAudioUnitEQ(numberOfBands: config.eq.bands.count)
            eq.globalGain = config.eq.globalGain

            for (i, bandConfig) in config.eq.bands.enumerated() {
                let band = eq.bands[i]
                band.filterType = AudioConfig.filterType(from: bandConfig.filterType)
                band.frequency = bandConfig.frequency
                band.gain = bandConfig.gain
                band.bandwidth = bandConfig.bandwidth
                band.bypass = false
            }

            engine.attach(eq)
            engine.connect(lastNode, to: eq, format: lastFormat)
            lastNode = eq
        }

        // Compressor
        if config.compressor.enabled {
            print("Attaching compressor...")
            let compressorDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let compressor = AVAudioUnitEffect(audioComponentDescription: compressorDesc)
            engine.attach(compressor)
            engine.connect(lastNode, to: compressor, format: lastFormat)

            // Set compressor parameters
            let au = compressor.audioUnit
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, config.compressor.threshold, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, config.compressor.headRoom, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, config.compressor.attackTime, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, config.compressor.releaseTime, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, config.compressor.masterGain, 0)

            lastNode = compressor
        }

        // Connect last processing node to output
        engine.connect(lastNode, to: engine.mainMixerNode, format: lastFormat)

        // 6. Start engine
        print("Starting audio engine...")
        try engine.start()
        print("VirtuMic is running. Audio chain: \(config.inputDevice) -> processing -> \(config.outputDevice)")
        print("Select '\(config.outputDevice)' as your microphone in meeting apps.")
    }

    func stop() {
        print("Stopping VirtuMic...")
        engine.stop()
        if aggregateDeviceID != 0 {
            DeviceManager.destroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        print("Stopped.")
    }

    private func setEngineDevice(_ deviceID: AudioDeviceID) throws {
        var deviceID = deviceID
        guard let outputUnit = engine.outputNode.audioUnit else {
            throw AudioDaemonError.noAudioUnit
        }

        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioDaemonError.deviceAssignFailed(status: status)
        }
    }
}

enum AudioDaemonError: LocalizedError {
    case noAudioUnit
    case deviceAssignFailed(status: OSStatus)
    case invalidFormat(description: String)

    var errorDescription: String? {
        switch self {
        case .noAudioUnit:
            return "Could not access engine output audio unit"
        case .deviceAssignFailed(let status):
            return "Failed to assign aggregate device to engine (CoreAudio error: \(status))"
        case .invalidFormat(let description):
            return description
        }
    }
}
