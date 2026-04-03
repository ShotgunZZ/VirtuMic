import AVFoundation
import CoreAudio
import AudioToolbox

final class AudioDaemon {
    private let config: AudioConfig
    private let inputEngine = AVAudioEngine()
    private let outputEngine = AVAudioEngine()

    // Lock-free ring buffer for passing audio between engines
    private var ringBuffer: UnsafeMutablePointer<Float>?
    private let ringBufferFrames = 88200 // 2 seconds at 44100
    private var writePos = 0
    private var readPos = 0
    private let bufferLock = NSLock()

    init(config: AudioConfig) {
        self.config = config
    }

    func start() throws {
        // 1. Find devices
        print("Looking for input device: '\(config.inputDevice)'...")
        let inputDevice = try DeviceManager.findDevice(matching: config.inputDevice, needsInput: true, needsOutput: false)
        print("  Found: \(inputDevice.name)")

        print("Looking for output device: '\(config.outputDevice)'...")
        let outputDevice = try DeviceManager.findDevice(matching: config.outputDevice, needsInput: false, needsOutput: true)
        print("  Found: \(outputDevice.name)")

        // 2. Set input engine to read from USB mic
        try inputEngine.inputNode.auAudioUnit.setDeviceID(inputDevice.id)

        // 3. Set output engine to write to BlackHole
        try outputEngine.outputNode.auAudioUnit.setDeviceID(outputDevice.id)

        // 4. Get the input format
        let inputFormat = inputEngine.inputNode.outputFormat(forBus: 0)
        let channels = Int(inputFormat.channelCount)
        let sampleRate = inputFormat.sampleRate
        print("Format: \(channels) ch, \(sampleRate) Hz")

        guard sampleRate > 0 && channels > 0 else {
            throw AudioDaemonError.invalidFormat(description: "Input node has invalid format: \(inputFormat)")
        }

        // 5. Allocate ring buffer
        ringBuffer = UnsafeMutablePointer<Float>.allocate(capacity: ringBufferFrames * channels)
        ringBuffer?.initialize(repeating: 0, count: ringBufferFrames * channels)

        // 6. Build processing chain on input engine
        var lastNode: AVAudioNode = inputEngine.inputNode
        let format = inputFormat

        // Noise Gate
        if config.noiseGate.enabled {
            print("Attaching noise gate...")
            if let gateNode = makeNoiseGateNode(
                config: config.noiseGate,
                sampleRate: Float(sampleRate)
            ) {
                inputEngine.attach(gateNode)
                inputEngine.connect(lastNode, to: gateNode, format: format)
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

            inputEngine.attach(eq)
            inputEngine.connect(lastNode, to: eq, format: format)
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
            inputEngine.attach(compressor)
            inputEngine.connect(lastNode, to: compressor, format: format)

            let au = compressor.audioUnit
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, config.compressor.threshold, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, config.compressor.headRoom, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, config.compressor.attackTime, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, config.compressor.releaseTime, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, config.compressor.masterGain, 0)

            lastNode = compressor
        }

        // Connect last processing node to mainMixerNode (required for engine to run)
        inputEngine.connect(lastNode, to: inputEngine.mainMixerNode, format: format)
        inputEngine.mainMixerNode.outputVolume = 0 // mute — we capture via tap instead

        // 7. Install tap on the last processing node to capture processed audio
        let ringBuf = self.ringBuffer!
        let ringSize = self.ringBufferFrames
        let lock = self.bufferLock
        let numChannels = channels

        // Capture writePos as a reference via the class
        let daemon = self

        lastNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)

            lock.lock()
            for i in 0..<frames {
                for ch in 0..<numChannels {
                    ringBuf[daemon.writePos * numChannels + ch] = channelData[ch][i]
                }
                daemon.writePos = (daemon.writePos + 1) % ringSize
            }
            lock.unlock()
        }

        // 8. Set up output engine with source node reading from ring buffer
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: UInt32(channels))!

        let sourceNode = AVAudioSourceNode(format: outputFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            lock.lock()
            for buffer in ablPointer {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let bufChannels = Int(buffer.mNumberChannels)
                for i in 0..<frames {
                    for ch in 0..<bufChannels {
                        if daemon.readPos != daemon.writePos {
                            data[i * bufChannels + ch] = ringBuf[daemon.readPos * numChannels + min(ch, numChannels - 1)]
                        } else {
                            data[i * bufChannels + ch] = 0 // underrun — output silence
                        }
                    }
                    if daemon.readPos != daemon.writePos {
                        daemon.readPos = (daemon.readPos + 1) % ringSize
                    }
                }
            }
            lock.unlock()

            return noErr
        }

        outputEngine.attach(sourceNode)
        outputEngine.connect(sourceNode, to: outputEngine.mainMixerNode, format: outputFormat)

        // 9. Start both engines
        print("Starting audio engines...")
        try inputEngine.start()
        try outputEngine.start()

        print("VirtuMic is running. Audio chain: \(config.inputDevice) -> processing -> \(config.outputDevice)")
        print("Select '\(config.outputDevice)' as your microphone in meeting apps.")
    }

    func stop() {
        print("Stopping VirtuMic...")
        inputEngine.inputNode.removeTap(onBus: 0)
        inputEngine.stop()
        outputEngine.stop()
        if let buf = ringBuffer {
            buf.deallocate()
            ringBuffer = nil
        }
        print("Stopped.")
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
