import AVFoundation
import CoreAudio
import AudioToolbox
import Combine
import os
import Atomics

private let log = Logger(subsystem: "com.virtumic.app2", category: "engine")

// MARK: - AudioEngine

final class AudioEngine: ObservableObject {
    @Published var isRunning = false
    @Published var isMonitoring = false
    @Published var inputLevel: Float = -60.0
    @Published var errorMessage: String?
    @Published var config: AudioConfig

    private var inputEngine = AVAudioEngine()
    private var outputEngine = AVAudioEngine()

    private var ringBuffer: UnsafeMutablePointer<Float>?
    private let ringBufferFrames = 88200
    private let writePos = ManagedAtomic<Int>(0)
    private let readPos = ManagedAtomic<Int>(0)
    private let atomicPeakLevel = ManagedAtomic<UInt32>(0)
    private var levelTimer: Timer?

    private var noiseGateAU: NoiseGateAudioUnit?
    private var eqNode: AVAudioUnitEQ?
    private var compressorNode: AVAudioUnitEffect?
    private var lastProcessingNode: AVAudioNode?
    private var engineSampleRate: Double = 48000
    private var engineChannels: Int = 2

    private let configPath: String
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        configPath = "\(home)/.config/virtual-mic/config.json"

        if let loaded = try? AudioConfig.load(from: configPath) {
            config = loaded
        } else {
            config = AudioConfig.defaultConfig
        }
    }

    // MARK: - Engine Lifecycle

    func start() {
        guard !isRunning else { return }
        do {
            try startEngines()
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        stopEngines()
        isRunning = false
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitor()
        } else {
            startMonitor()
        }
    }

    private func startEngines() throws {
        setbuf(stdout, nil)
        inputEngine = AVAudioEngine()
        outputEngine = AVAudioEngine()
        writePos.store(0, ordering: .relaxed)
        readPos.store(0, ordering: .relaxed)
        atomicPeakLevel.store(Float(-60).bitPattern, ordering: .relaxed)

        let inputDevice = try DeviceManager.findDevice(matching: config.inputDevice, needsInput: true, needsOutput: false)
        let outputDevice = try DeviceManager.findDevice(matching: config.outputDevice, needsInput: false, needsOutput: true)
        log.info("[VirtuMic] Input: \(inputDevice.name) (ID: \(inputDevice.id))")
        log.info("[VirtuMic] Output: \(outputDevice.name) (ID: \(outputDevice.id))")

        // Use system default input device (user should set fifine in System Settings)
        // AVAudioEngine's inputNode automatically uses the system default
        log.info("[VirtuMic] Using system default input device (no override)")

        // Set output device to BlackHole (must use auAudioUnit — audioUnit is nil on fresh engine)
        try outputEngine.outputNode.auAudioUnit.setDeviceID(outputDevice.id)
        log.info("[VirtuMic] Set output device to BlackHole")

        // Use inputNode's reported format (engine handles resampling internally)
        let inputFormat = inputEngine.inputNode.outputFormat(forBus: 0)
        let channels = Int(inputFormat.channelCount)
        let sampleRate = inputFormat.sampleRate
        log.info("[VirtuMic] Using engine format: \(channels) ch, \(sampleRate) Hz")

        guard sampleRate > 0 && channels > 0 else {
            throw AudioEngineError.invalidFormat
        }
        engineSampleRate = sampleRate
        engineChannels = channels

        ringBuffer = UnsafeMutablePointer<Float>.allocate(capacity: ringBufferFrames * channels)
        ringBuffer?.initialize(repeating: 0, count: ringBufferFrames * channels)

        var lastNode: AVAudioNode = inputEngine.inputNode
        let format = inputFormat

        // Noise Gate — always attach, control via threshold
        if let gateNode = makeNoiseGateNode(config: config.noiseGate, sampleRate: Float(sampleRate)) {
            if let au = gateNode.auAudioUnit as? NoiseGateAudioUnit {
                noiseGateAU = au
                if !config.noiseGate.enabled {
                    au.dsp?.setThreshold(dB: -96)
                }
            }
            inputEngine.attach(gateNode)
            inputEngine.connect(lastNode, to: gateNode, format: format)
            lastNode = gateNode
        }

        // EQ — always attach, control via bypass
        let eq = AVAudioUnitEQ(numberOfBands: max(config.eq.bands.count, 1))
        eqNode = eq
        eq.globalGain = config.eq.globalGain
        eq.bypass = !config.eq.enabled
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

        // Compressor — always attach, control via bypass
        let compressorDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let compressor = AVAudioUnitEffect(audioComponentDescription: compressorDesc)
        compressorNode = compressor
        compressor.bypass = !config.compressor.enabled
        inputEngine.attach(compressor)
        inputEngine.connect(lastNode, to: compressor, format: format)
        applyCompressorParams()
        lastNode = compressor

        inputEngine.connect(lastNode, to: inputEngine.mainMixerNode, format: format)
        inputEngine.mainMixerNode.outputVolume = 0.001  // near-silent playback through speakers
        lastProcessingNode = lastNode

        // Install tap on last processing node (BEFORE volume reduction)
        // This gives full-volume processed audio for the ring buffer and level meter
        let ringBuf = ringBuffer!
        let ringSize = ringBufferFrames
        let numChannels = channels
        let atomicWP = writePos
        let atomicRP = readPos
        let atomicPeak = atomicPeakLevel

        var tapCount = 0
        lastNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)

            tapCount += 1
            if tapCount <= 5 || tapCount % 100 == 0 {
                var maxSample: Float = 0
                for i in 0..<frames { maxSample = max(maxSample, fabsf(channelData[0][i])) }
                log.info("[VirtuMic] Tap #\(tapCount): frames=\(frames), maxSample=\(maxSample), writePos=\(atomicWP.load(ordering: .relaxed))")
            }

            // Level metering — atomic store, zero allocations
            var maxLevel: Float = 0
            for i in 0..<frames {
                let level = fabsf(channelData[0][i])
                if level > maxLevel { maxLevel = level }
            }
            let db = maxLevel > 0 ? 20 * log10f(maxLevel) : Float(-60)
            atomicPeak.store(db.bitPattern, ordering: .relaxed)

            // Lock-free write to ring buffer
            let tapChannels = min(Int(buffer.format.channelCount), numChannels)
            var wp = atomicWP.load(ordering: .relaxed)
            for i in 0..<frames {
                for ch in 0..<numChannels {
                    ringBuf[wp * numChannels + ch] = channelData[min(ch, tapChannels - 1)][i]
                }
                wp = (wp + 1) % ringSize
            }
            atomicWP.store(wp, ordering: .releasing)
        }

        // Output engine — lock-free reader with underrun smoothing
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: UInt32(channels))!

        var srcCount = 0
        var lastSamples = [Float](repeating: 0, count: numChannels)
        var fadeGain: Float = 0

        let sourceNode = AVAudioSourceNode(format: outputFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            let wp = atomicWP.load(ordering: .acquiring)
            var rp = atomicRP.load(ordering: .relaxed)
            let preReadPos = rp

            for buffer in ablPointer {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let bufChannels = Int(buffer.mNumberChannels)
                for i in 0..<frames {
                    if rp != wp {
                        // Data available — read from ring buffer
                        for ch in 0..<bufChannels {
                            let sample = ringBuf[rp * numChannels + min(ch, numChannels - 1)]
                            data[i * bufChannels + ch] = sample
                            lastSamples[min(ch, numChannels - 1)] = sample
                        }
                        rp = (rp + 1) % ringSize
                        fadeGain = 1.0
                    } else {
                        // Underrun — smooth fade-out from last sample
                        fadeGain *= 0.95
                        for ch in 0..<bufChannels {
                            data[i * bufChannels + ch] = lastSamples[min(ch, numChannels - 1)] * fadeGain
                        }
                    }
                }
            }

            atomicRP.store(rp, ordering: .releasing)

            srcCount += 1
            if srcCount <= 5 || srcCount % 100 == 0 {
                var outMax: Float = 0
                if let firstBuf = ablPointer.first, let d = firstBuf.mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<frames { outMax = max(outMax, fabsf(d[i])) }
                }
                log.info("[VirtuMic] Src #\(srcCount): frames=\(frames), readPos=\(preReadPos)→\(rp), writePos=\(wp), outMax=\(outMax)")
            }

            return noErr
        }

        outputEngine.attach(sourceNode)
        outputEngine.connect(sourceNode, to: outputEngine.mainMixerNode, format: outputFormat)

        try inputEngine.start()
        try outputEngine.start()
        log.info("[VirtuMic] Both engines started successfully!")

        // Poll atomic peak level from main thread (no allocation on audio thread)
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let bits = self.atomicPeakLevel.load(ordering: .relaxed)
            self.inputLevel = Float(bitPattern: bits)
        }
    }


    private func startMonitor() {
        guard isRunning else { return }
        inputEngine.mainMixerNode.outputVolume = 1.0
        isMonitoring = true
    }

    private func stopMonitor() {
        inputEngine.mainMixerNode.outputVolume = 0.001
        isMonitoring = false
    }

    private func stopEngines() {
        isMonitoring = false
        lastProcessingNode?.removeTap(onBus: 0)
        inputEngine.stop()
        outputEngine.stop()
        noiseGateAU = nil
        eqNode = nil
        compressorNode = nil
        lastProcessingNode = nil
        levelTimer?.invalidate()
        levelTimer = nil
        if let buf = ringBuffer {
            buf.deallocate()
            ringBuffer = nil
        }
        inputLevel = -60
    }

    // MARK: - Noise Gate

    func setNoiseGateEnabled(_ enabled: Bool) {
        config.noiseGate.enabled = enabled
        if enabled {
            noiseGateAU?.dsp?.setThreshold(dB: config.noiseGate.thresholdDB)
        } else {
            noiseGateAU?.dsp?.setThreshold(dB: -96)
        }
        scheduleSave()
    }

    func setNoiseGateThreshold(_ dB: Float) {
        config.noiseGate.thresholdDB = dB
        if config.noiseGate.enabled {
            noiseGateAU?.dsp?.setThreshold(dB: dB)
        }
        scheduleSave()
    }

    func setNoiseGateAttack(_ time: Float) {
        config.noiseGate.attackTime = time
        noiseGateAU?.dsp?.setAttack(time: time)
        scheduleSave()
    }

    func setNoiseGateRelease(_ time: Float) {
        config.noiseGate.releaseTime = time
        noiseGateAU?.dsp?.setRelease(time: time)
        scheduleSave()
    }

    func setNoiseGateHold(_ time: Float) {
        config.noiseGate.holdTime = time
        noiseGateAU?.dsp?.setHold(time: time)
        scheduleSave()
    }

    // MARK: - EQ

    func setEQEnabled(_ enabled: Bool) {
        config.eq.enabled = enabled
        eqNode?.bypass = !enabled
        scheduleSave()
    }

    func setEQGlobalGain(_ gain: Float) {
        config.eq.globalGain = gain
        eqNode?.globalGain = gain
        scheduleSave()
    }

    func setEQBand(index: Int, filterType: AVAudioUnitEQFilterType, frequency: Float, gain: Float, bandwidth: Float) {
        guard index < config.eq.bands.count, let eq = eqNode, index < eq.bands.count else { return }

        config.eq.bands[index] = EQBandConfig(
            filterType: AudioConfig.filterTypeString(from: filterType),
            frequency: frequency,
            gain: gain,
            bandwidth: bandwidth
        )

        let band = eq.bands[index]
        band.filterType = filterType
        band.frequency = frequency
        band.gain = gain
        band.bandwidth = bandwidth
        band.bypass = false
        scheduleSave()
    }

    // MARK: - Compressor

    func setCompressorEnabled(_ enabled: Bool) {
        config.compressor.enabled = enabled
        compressorNode?.bypass = !enabled
        scheduleSave()
    }

    func setCompressorThreshold(_ value: Float) {
        config.compressor.threshold = value
        applyCompressorParam(kDynamicsProcessorParam_Threshold, value)
        scheduleSave()
    }

    func setCompressorHeadroom(_ value: Float) {
        config.compressor.headRoom = value
        applyCompressorParam(kDynamicsProcessorParam_HeadRoom, value)
        scheduleSave()
    }

    func setCompressorAttack(_ value: Float) {
        config.compressor.attackTime = value
        applyCompressorParam(kDynamicsProcessorParam_AttackTime, value)
        scheduleSave()
    }

    func setCompressorRelease(_ value: Float) {
        config.compressor.releaseTime = value
        applyCompressorParam(kDynamicsProcessorParam_ReleaseTime, value)
        scheduleSave()
    }

    func setCompressorGain(_ value: Float) {
        config.compressor.masterGain = value
        applyCompressorParam(kDynamicsProcessorParam_OverallGain, value)
        scheduleSave()
    }

    private func applyCompressorParams() {
        let c = config.compressor
        applyCompressorParam(kDynamicsProcessorParam_Threshold, c.threshold)
        applyCompressorParam(kDynamicsProcessorParam_HeadRoom, c.headRoom)
        applyCompressorParam(kDynamicsProcessorParam_AttackTime, c.attackTime)
        applyCompressorParam(kDynamicsProcessorParam_ReleaseTime, c.releaseTime)
        applyCompressorParam(kDynamicsProcessorParam_OverallGain, c.masterGain)
    }

    private func applyCompressorParam(_ param: AudioUnitParameterID, _ value: Float) {
        guard let au = compressorNode?.audioUnit else { return }
        AudioUnitSetParameter(au, param, kAudioUnitScope_Global, 0, value, 0)
    }

    // MARK: - Config Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            try? self.config.save(to: self.configPath)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
}

// MARK: - Errors

enum AudioEngineError: LocalizedError {
    case invalidFormat
    case noAudioUnit
    case deviceAssignFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Input device has invalid audio format"
        case .noAudioUnit:
            return "Could not access underlying AudioUnit"
        case .deviceAssignFailed(let status):
            return "Failed to assign audio device (CoreAudio error: \(status))"
        }
    }
}
