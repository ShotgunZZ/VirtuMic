import AVFoundation
import AudioToolbox

// MARK: - DSP Logic (testable, no AU dependency)

final class NoiseGateDSP {
    private let thresholdLinear: Float
    private let attackCoeff: Float
    private let releaseCoeff: Float
    private let holdSamples: Int

    private var envelope: Float = 0.0
    private var holdCounter: Int = 0

    init(thresholdDB: Float, attackTime: Float, releaseTime: Float, holdTime: Float, sampleRate: Float) {
        self.thresholdLinear = powf(10.0, thresholdDB / 20.0)
        self.attackCoeff = expf(-1.0 / (attackTime * sampleRate))
        self.releaseCoeff = expf(-1.0 / (releaseTime * sampleRate))
        self.holdSamples = Int(holdTime * sampleRate)
    }

    func process(_ samples: inout [Float], frameCount: Int) {
        for i in 0..<frameCount {
            let inputLevel = fabsf(samples[i])

            if inputLevel >= thresholdLinear {
                holdCounter = holdSamples
            }

            let gateOpen = holdCounter > 0
            if gateOpen {
                holdCounter -= 1
            }

            let target: Float = gateOpen ? 1.0 : 0.0
            if target > envelope {
                envelope = attackCoeff * envelope + (1.0 - attackCoeff) * target
            } else {
                envelope = releaseCoeff * envelope + (1.0 - releaseCoeff) * target
            }

            samples[i] *= envelope
        }
    }

    func processBuffer(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let inputLevel = fabsf(buffer[i])

            if inputLevel >= thresholdLinear {
                holdCounter = holdSamples
            }

            let gateOpen = holdCounter > 0
            if gateOpen {
                holdCounter -= 1
            }

            let target: Float = gateOpen ? 1.0 : 0.0
            if target > envelope {
                envelope = attackCoeff * envelope + (1.0 - attackCoeff) * target
            } else {
                envelope = releaseCoeff * envelope + (1.0 - releaseCoeff) * target
            }

            buffer[i] *= envelope
        }
    }
}

// MARK: - AUAudioUnit wrapper for AVAudioEngine integration

final class NoiseGateAudioUnit: AUAudioUnit {
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _outputBusArray: AUAudioUnitBusArray!
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    var dsp: NoiseGateDSP?

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        _inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var inputBusses: AUAudioUnitBusArray { _inputBusArray }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let dsp = self.dsp
        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, renderEvent, pullInputBlock in
            guard let pull = pullInputBlock else { return kAudioUnitErr_NoConnection }

            let status = pull(actionFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }

            guard let dsp = dsp else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in ablPointer {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                dsp.processBuffer(samples, frameCount: Int(frameCount))
            }

            return noErr
        }
    }
}

// MARK: - AVAudioEngine node wrapper

func makeNoiseGateNode(config: NoiseGateConfig, sampleRate: Float) -> AVAudioUnitEffect? {
    let desc = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: FourCharCode(truncating: "nGte"),
        componentManufacturer: FourCharCode(truncating: "VrMc"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    AUAudioUnit.registerSubclass(
        NoiseGateAudioUnit.self,
        as: desc,
        name: "VirtuMic Noise Gate",
        version: 1
    )

    let node = AVAudioUnitEffect(audioComponentDescription: desc)

    if let au = node.auAudioUnit as? NoiseGateAudioUnit {
        au.dsp = NoiseGateDSP(
            thresholdDB: config.thresholdDB,
            attackTime: config.attackTime,
            releaseTime: config.releaseTime,
            holdTime: config.holdTime,
            sampleRate: sampleRate
        )
    }

    return node
}

// MARK: - FourCharCode helper

private extension FourCharCode {
    init(truncating string: String) {
        var result: FourCharCode = 0
        for (i, char) in string.utf8.prefix(4).enumerated() {
            result |= FourCharCode(char) << (8 * (3 - i))
        }
        self = result
    }
}
