# VirtuMic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight macOS daemon that processes USB mic audio (noise gate, EQ, compressor) and routes it to BlackHole for use in meeting apps.

**Architecture:** Swift CLI using AVAudioEngine with a private aggregate device (USB mic + BlackHole). Audio chain: inputNode -> NoiseGate (custom AU) -> EQ (AVAudioUnitEQ) -> Compressor (AUDynamicsProcessor) -> outputNode. All settings from a JSON config file. Runs as a LaunchAgent.

**Tech Stack:** Swift 5.9+, Swift Package Manager, AVFoundation, CoreAudio, Accelerate frameworks. No third-party dependencies.

---

## File Map

| File | Responsibility |
|------|---------------|
| `Package.swift` | SPM manifest, macOS 13+ target, system frameworks |
| `Sources/VirtuMic/Config.swift` | Codable structs, JSON loading, validation |
| `Sources/VirtuMic/DeviceManager.swift` | CoreAudio device enumeration, aggregate device creation/destruction |
| `Sources/VirtuMic/NoiseGate.swift` | Custom AUAudioUnit subclass + DSP render block |
| `Sources/VirtuMic/AudioDaemon.swift` | AVAudioEngine setup, processing chain wiring, start/stop |
| `Sources/VirtuMic/main.swift` | Entry point, CLI arg parsing, signal handlers, dispatchMain() |
| `Tests/VirtuMicTests/ConfigTests.swift` | Config loading, validation, error cases |
| `Tests/VirtuMicTests/NoiseGateTests.swift` | Noise gate DSP logic unit tests |
| `config/default-config.json` | Example config with sensible defaults |
| `install.sh` | Build release binary, copy to /usr/local/bin, install LaunchAgent plist |

---

### Task 1: Project Scaffold + Package.swift

**Files:**
- Create: `Package.swift`
- Create: `Sources/VirtuMic/main.swift` (minimal placeholder)
- Create: `Tests/VirtuMicTests/ConfigTests.swift` (minimal placeholder)

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtuMic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VirtuMic",
            path: "Sources/VirtuMic",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Accelerate"),
            ]
        ),
        .testTarget(
            name: "VirtuMicTests",
            dependencies: ["VirtuMic"],
            path: "Tests/VirtuMicTests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal main.swift**

```swift
import Foundation

print("VirtuMic starting...")
```

- [ ] **Step 3: Create placeholder test file**

```swift
import XCTest

final class ConfigTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Verify it builds and tests pass**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift build 2>&1`
Expected: Build Succeeded

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test 2>&1`
Expected: Test Suite passed

- [ ] **Step 5: Initialize git and commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git init
echo ".build/\n.swiftpm/\n*.o\n*.swp\nDerivedData/" > .gitignore
git add Package.swift Sources/ Tests/ .gitignore docs/
git commit -m "feat: scaffold VirtuMic Swift package"
```

---

### Task 2: Config — Codable Structs + JSON Loading

**Files:**
- Create: `Sources/VirtuMic/Config.swift`
- Modify: `Tests/VirtuMicTests/ConfigTests.swift`

- [ ] **Step 1: Write failing tests for config loading**

Replace `Tests/VirtuMicTests/ConfigTests.swift` with:

```swift
import XCTest
@testable import VirtuMic

final class ConfigTests: XCTestCase {

    func testDecodeValidConfig() throws {
        let json = """
        {
          "inputDevice": "USB Mic",
          "outputDevice": "BlackHole 2ch",
          "sampleRate": 48000,
          "noiseGate": {
            "enabled": true,
            "thresholdDB": -40.0,
            "attackTime": 0.002,
            "releaseTime": 0.05,
            "holdTime": 0.1
          },
          "eq": {
            "enabled": true,
            "globalGain": 0.0,
            "bands": [
              { "filterType": "highPass", "frequency": 80, "gain": 0, "bandwidth": 0.5 }
            ]
          },
          "compressor": {
            "enabled": true,
            "threshold": -20.0,
            "headRoom": 5.0,
            "attackTime": 0.01,
            "releaseTime": 0.1,
            "masterGain": 0.0
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AudioConfig.self, from: json)
        XCTAssertEqual(config.inputDevice, "USB Mic")
        XCTAssertEqual(config.outputDevice, "BlackHole 2ch")
        XCTAssertEqual(config.sampleRate, 48000)
        XCTAssertTrue(config.noiseGate.enabled)
        XCTAssertEqual(config.noiseGate.thresholdDB, -40.0)
        XCTAssertEqual(config.eq.bands.count, 1)
        XCTAssertEqual(config.eq.bands[0].filterType, "highPass")
        XCTAssertEqual(config.eq.bands[0].frequency, 80.0)
        XCTAssertTrue(config.compressor.enabled)
        XCTAssertEqual(config.compressor.threshold, -20.0)
    }

    func testDecodeInvalidFilterType() throws {
        let json = """
        {
          "inputDevice": "Mic",
          "outputDevice": "BlackHole 2ch",
          "sampleRate": 48000,
          "noiseGate": { "enabled": false, "thresholdDB": -40, "attackTime": 0.002, "releaseTime": 0.05, "holdTime": 0.1 },
          "eq": {
            "enabled": true,
            "globalGain": 0.0,
            "bands": [
              { "filterType": "invalidType", "frequency": 80, "gain": 0, "bandwidth": 0.5 }
            ]
          },
          "compressor": { "enabled": false, "threshold": -20, "headRoom": 5, "attackTime": 0.01, "releaseTime": 0.1, "masterGain": 0 }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AudioConfig.self, from: json)
        XCTAssertThrowsError(try config.validate())
    }

    func testDecodeFrequencyOutOfRange() throws {
        let json = """
        {
          "inputDevice": "Mic",
          "outputDevice": "BlackHole 2ch",
          "sampleRate": 48000,
          "noiseGate": { "enabled": false, "thresholdDB": -40, "attackTime": 0.002, "releaseTime": 0.05, "holdTime": 0.1 },
          "eq": {
            "enabled": true,
            "globalGain": 0.0,
            "bands": [
              { "filterType": "parametric", "frequency": 5, "gain": 0, "bandwidth": 0.5 }
            ]
          },
          "compressor": { "enabled": false, "threshold": -20, "headRoom": 5, "attackTime": 0.01, "releaseTime": 0.1, "masterGain": 0 }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AudioConfig.self, from: json)
        XCTAssertThrowsError(try config.validate())
    }

    func testLoadConfigFromFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let configPath = tmpDir.appendingPathComponent("test-config.json").path
        let json = """
        {
          "inputDevice": "Test Mic",
          "outputDevice": "BlackHole 2ch",
          "sampleRate": 44100,
          "noiseGate": { "enabled": false, "thresholdDB": -40, "attackTime": 0.002, "releaseTime": 0.05, "holdTime": 0.1 },
          "eq": { "enabled": false, "globalGain": 0, "bands": [] },
          "compressor": { "enabled": false, "threshold": -20, "headRoom": 5, "attackTime": 0.01, "releaseTime": 0.1, "masterGain": 0 }
        }
        """
        try json.write(toFile: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let config = try AudioConfig.load(from: configPath)
        XCTAssertEqual(config.inputDevice, "Test Mic")
        XCTAssertEqual(config.sampleRate, 44100)
    }

    func testLoadConfigMissingFile() {
        XCTAssertThrowsError(try AudioConfig.load(from: "/nonexistent/path.json"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test 2>&1`
Expected: FAIL — `AudioConfig` type not found

- [ ] **Step 3: Implement Config.swift**

Create `Sources/VirtuMic/Config.swift`:

```swift
import Foundation
import AVFoundation

struct NoiseGateConfig: Codable {
    let enabled: Bool
    let thresholdDB: Float
    let attackTime: Float
    let releaseTime: Float
    let holdTime: Float
}

struct EQBandConfig: Codable {
    let filterType: String
    let frequency: Float
    let gain: Float
    let bandwidth: Float
}

struct EQConfig: Codable {
    let enabled: Bool
    let globalGain: Float
    let bands: [EQBandConfig]
}

struct CompressorConfig: Codable {
    let enabled: Bool
    let threshold: Float
    let headRoom: Float
    let attackTime: Float
    let releaseTime: Float
    let masterGain: Float
}

struct AudioConfig: Codable {
    let inputDevice: String
    let outputDevice: String
    let sampleRate: Double
    let noiseGate: NoiseGateConfig
    let eq: EQConfig
    let compressor: CompressorConfig

    static let validFilterTypes: Set<String> = [
        "parametric", "lowPass", "highPass",
        "resonantLowPass", "resonantHighPass",
        "bandPass", "bandStop",
        "lowShelf", "highShelf",
        "resonantLowShelf", "resonantHighShelf"
    ]

    static func load(from path: String) throws -> AudioConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AudioConfig.self, from: data)
    }

    func validate() throws {
        let maxFreq = Float(sampleRate / 2.0)

        if eq.enabled {
            for (i, band) in eq.bands.enumerated() {
                guard Self.validFilterTypes.contains(band.filterType) else {
                    throw ConfigError.invalidFilterType(band: i, type: band.filterType)
                }
                guard band.frequency >= 20 && band.frequency <= maxFreq else {
                    throw ConfigError.outOfRange(
                        parameter: "eq.bands[\(i)].frequency",
                        value: band.frequency,
                        range: "20...\(maxFreq)"
                    )
                }
                guard band.gain >= -96 && band.gain <= 24 else {
                    throw ConfigError.outOfRange(
                        parameter: "eq.bands[\(i)].gain",
                        value: band.gain,
                        range: "-96...24"
                    )
                }
                guard band.bandwidth >= 0.05 && band.bandwidth <= 5.0 else {
                    throw ConfigError.outOfRange(
                        parameter: "eq.bands[\(i)].bandwidth",
                        value: band.bandwidth,
                        range: "0.05...5.0"
                    )
                }
            }
            guard eq.globalGain >= -96 && eq.globalGain <= 24 else {
                throw ConfigError.outOfRange(
                    parameter: "eq.globalGain",
                    value: eq.globalGain,
                    range: "-96...24"
                )
            }
        }

        if noiseGate.enabled {
            guard noiseGate.thresholdDB >= -96 && noiseGate.thresholdDB <= 0 else {
                throw ConfigError.outOfRange(
                    parameter: "noiseGate.thresholdDB",
                    value: noiseGate.thresholdDB,
                    range: "-96...0"
                )
            }
            guard noiseGate.attackTime >= 0.0001 && noiseGate.attackTime <= 0.1 else {
                throw ConfigError.outOfRange(
                    parameter: "noiseGate.attackTime",
                    value: noiseGate.attackTime,
                    range: "0.0001...0.1"
                )
            }
            guard noiseGate.releaseTime >= 0.01 && noiseGate.releaseTime <= 1.0 else {
                throw ConfigError.outOfRange(
                    parameter: "noiseGate.releaseTime",
                    value: noiseGate.releaseTime,
                    range: "0.01...1.0"
                )
            }
            guard noiseGate.holdTime >= 0.0 && noiseGate.holdTime <= 2.0 else {
                throw ConfigError.outOfRange(
                    parameter: "noiseGate.holdTime",
                    value: noiseGate.holdTime,
                    range: "0.0...2.0"
                )
            }
        }

        if compressor.enabled {
            guard compressor.threshold >= -40 && compressor.threshold <= 20 else {
                throw ConfigError.outOfRange(
                    parameter: "compressor.threshold",
                    value: compressor.threshold,
                    range: "-40...20"
                )
            }
            guard compressor.headRoom >= 0.1 && compressor.headRoom <= 40 else {
                throw ConfigError.outOfRange(
                    parameter: "compressor.headRoom",
                    value: compressor.headRoom,
                    range: "0.1...40"
                )
            }
            guard compressor.attackTime >= 0.0001 && compressor.attackTime <= 0.2 else {
                throw ConfigError.outOfRange(
                    parameter: "compressor.attackTime",
                    value: compressor.attackTime,
                    range: "0.0001...0.2"
                )
            }
            guard compressor.releaseTime >= 0.01 && compressor.releaseTime <= 3.0 else {
                throw ConfigError.outOfRange(
                    parameter: "compressor.releaseTime",
                    value: compressor.releaseTime,
                    range: "0.01...3.0"
                )
            }
            guard compressor.masterGain >= -40 && compressor.masterGain <= 40 else {
                throw ConfigError.outOfRange(
                    parameter: "compressor.masterGain",
                    value: compressor.masterGain,
                    range: "-40...40"
                )
            }
        }
    }

    static func filterType(from string: String) -> AVAudioUnitEQFilterType {
        switch string {
        case "parametric": return .parametric
        case "lowPass": return .lowPass
        case "highPass": return .highPass
        case "resonantLowPass": return .resonantLowPass
        case "resonantHighPass": return .resonantHighPass
        case "bandPass": return .bandPass
        case "bandStop": return .bandStop
        case "lowShelf": return .lowShelf
        case "highShelf": return .highShelf
        case "resonantLowShelf": return .resonantLowShelf
        case "resonantHighShelf": return .resonantHighShelf
        default: return .parametric
        }
    }
}

enum ConfigError: LocalizedError {
    case invalidFilterType(band: Int, type: String)
    case outOfRange(parameter: String, value: Float, range: String)

    var errorDescription: String? {
        switch self {
        case .invalidFilterType(let band, let type):
            return "Invalid filter type '\(type)' in eq.bands[\(band)]. Valid types: \(AudioConfig.validFilterTypes.sorted().joined(separator: ", "))"
        case .outOfRange(let parameter, let value, let range):
            return "Parameter '\(parameter)' value \(value) is out of range \(range)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test 2>&1`
Expected: All 4 tests pass

- [ ] **Step 5: Commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git add Sources/VirtuMic/Config.swift Tests/VirtuMicTests/ConfigTests.swift
git commit -m "feat: add config loading with validation and tests"
```

---

### Task 3: Noise Gate DSP Logic

**Files:**
- Create: `Sources/VirtuMic/NoiseGate.swift`
- Create: `Tests/VirtuMicTests/NoiseGateTests.swift`

- [ ] **Step 1: Write failing tests for noise gate DSP**

Create `Tests/VirtuMicTests/NoiseGateTests.swift`:

```swift
import XCTest
@testable import VirtuMic

final class NoiseGateTests: XCTestCase {

    func testSilentInputStaysSilent() {
        let gate = NoiseGateDSP(
            thresholdDB: -40.0,
            attackTime: 0.002,
            releaseTime: 0.05,
            holdTime: 0.1,
            sampleRate: 48000.0
        )

        var samples = [Float](repeating: 0.0, count: 4800) // 100ms of silence
        gate.process(&samples, frameCount: 4800)

        for sample in samples {
            XCTAssertEqual(sample, 0.0, accuracy: 0.0001)
        }
    }

    func testLoudSignalPassesThrough() {
        let gate = NoiseGateDSP(
            thresholdDB: -40.0,
            attackTime: 0.001,
            releaseTime: 0.05,
            holdTime: 0.1,
            sampleRate: 48000.0
        )

        // Generate a loud sine wave (well above -40 dB threshold)
        let amplitude: Float = 0.5
        var samples = (0..<4800).map { i in
            amplitude * sin(Float(i) * 2.0 * .pi * 440.0 / 48000.0)
        }
        let originalRMS = rms(samples)

        gate.process(&samples, frameCount: 4800)
        let processedRMS = rms(samples)

        // After attack settles, most of the signal should pass through
        // Allow some loss during attack phase
        XCTAssertGreaterThan(processedRMS, originalRMS * 0.7)
    }

    func testQuietSignalGetsSuppressed() {
        let gate = NoiseGateDSP(
            thresholdDB: -20.0,  // high threshold
            attackTime: 0.001,
            releaseTime: 0.01,
            holdTime: 0.01,
            sampleRate: 48000.0
        )

        // Signal at -40 dB (below -20 dB threshold)
        let amplitude: Float = 0.01
        var samples = (0..<48000).map { i in
            amplitude * sin(Float(i) * 2.0 * .pi * 440.0 / 48000.0)
        }

        gate.process(&samples, frameCount: 48000)
        let processedRMS = rms(samples)

        // Should be heavily attenuated
        XCTAssertLessThan(processedRMS, amplitude * 0.1)
    }

    func testHoldKeepsGateOpen() {
        let holdTime: Float = 0.1  // 100ms hold
        let sampleRate: Float = 48000.0
        let gate = NoiseGateDSP(
            thresholdDB: -40.0,
            attackTime: 0.001,
            releaseTime: 0.05,
            holdTime: holdTime,
            sampleRate: sampleRate
        )

        // First: feed loud signal to open the gate
        let amplitude: Float = 0.5
        var loudSamples = (0..<4800).map { i in
            amplitude * sin(Float(i) * 2.0 * .pi * 440.0 / sampleRate)
        }
        gate.process(&loudSamples, frameCount: 4800)

        // Then: feed silence — gate should stay open during hold period
        let holdSampleCount = Int(holdTime * sampleRate * 0.5) // half of hold time
        var silentSamples = [Float](repeating: 0.001, count: holdSampleCount)
        gate.process(&silentSamples, frameCount: holdSampleCount)

        // Envelope should still be mostly open during hold
        // The tiny signal * high envelope should be close to original
        let processedRMS = rms(silentSamples)
        XCTAssertGreaterThan(processedRMS, 0.0005)
    }

    private func rms(_ samples: [Float]) -> Float {
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test --filter NoiseGateTests 2>&1`
Expected: FAIL — `NoiseGateDSP` type not found

- [ ] **Step 3: Implement NoiseGate.swift**

Create `Sources/VirtuMic/NoiseGate.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test --filter NoiseGateTests 2>&1`
Expected: All 4 tests pass

- [ ] **Step 5: Run all tests**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test 2>&1`
Expected: All 8 tests pass (4 config + 4 noise gate)

- [ ] **Step 6: Commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git add Sources/VirtuMic/NoiseGate.swift Tests/VirtuMicTests/NoiseGateTests.swift
git commit -m "feat: add noise gate DSP with custom AUAudioUnit wrapper"
```

---

### Task 4: Device Manager — CoreAudio Device Enumeration + Aggregate Device

**Files:**
- Create: `Sources/VirtuMic/DeviceManager.swift`

- [ ] **Step 1: Implement DeviceManager.swift**

This module interacts directly with CoreAudio hardware — it cannot be meaningfully unit tested without real audio devices. We test it manually.

Create `Sources/VirtuMic/DeviceManager.swift`:

```swift
import CoreAudio
import Foundation

struct AudioDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}

enum DeviceError: LocalizedError {
    case deviceNotFound(name: String, available: [String])
    case aggregateCreationFailed(status: OSStatus)
    case noUID(deviceID: AudioDeviceID)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let name, let available):
            return "Audio device '\(name)' not found. Available devices: \(available.joined(separator: ", "))"
        case .aggregateCreationFailed(let status):
            return "Failed to create aggregate device (CoreAudio error: \(status))"
        case .noUID(let deviceID):
            return "Could not get UID for device ID \(deviceID)"
        }
    }
}

enum DeviceManager {

    static func listDevices() -> [AudioDevice] {
        let deviceIDs = getDeviceIDs()
        return deviceIDs.compactMap { id in
            guard let uid = getStringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID),
                  let name = getStringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceNameCFString)
            else { return nil }

            let hasInput = channelCount(deviceID: id, scope: kAudioDevicePropertyScopeInput) > 0
            let hasOutput = channelCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput) > 0

            return AudioDevice(id: id, uid: uid, name: name, hasInput: hasInput, hasOutput: hasOutput)
        }
    }

    static func findDevice(matching name: String, needsInput: Bool, needsOutput: Bool) throws -> AudioDevice {
        let devices = listDevices()
        if let device = devices.first(where: {
            $0.name.localizedCaseInsensitiveContains(name) &&
            (!needsInput || $0.hasInput) &&
            (!needsOutput || $0.hasOutput)
        }) {
            return device
        }

        let relevantNames = devices
            .filter { (!needsInput || $0.hasInput) && (!needsOutput || $0.hasOutput) }
            .map { $0.name }
        throw DeviceError.deviceNotFound(name: name, available: relevantNames)
    }

    static func createAggregateDevice(inputUID: String, outputUID: String) throws -> AudioDeviceID {
        let subDevices: [[String: Any]] = [
            [
                kAudioSubDeviceUIDKey as String: inputUID,
                kAudioSubDeviceDriftCompensationKey as String: 0,  // master clock, no drift comp
            ],
            [
                kAudioSubDeviceUIDKey as String: outputUID,
                kAudioSubDeviceDriftCompensationKey as String: 1,  // enable drift comp for virtual device
            ],
        ]

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "VirtuMicAggregate",
            kAudioAggregateDeviceUIDKey as String: "com.virtumic.aggregate",
            kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey as String: inputUID,
            kAudioAggregateDeviceIsPrivateKey as String: 1,
        ]

        var aggregateDeviceID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &aggregateDeviceID
        )

        guard status == noErr else {
            throw DeviceError.aggregateCreationFailed(status: status)
        }

        // Give CoreAudio time to fully register the device
        CFRunLoopRunInMode(.defaultMode, 0.1, false)

        return aggregateDeviceID
    }

    static func destroyAggregateDevice(_ deviceID: AudioDeviceID) {
        AudioHardwareDestroyAggregateDevice(deviceID)
    }

    // MARK: - Private helpers

    private static func getDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs
    }

    private static func getStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var name: CFString? = nil
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        return status == noErr ? name as String? : nil
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return 0 }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else { return 0 }

        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self).pointee
        var totalChannels = 0
        withUnsafePointer(to: bufferList.mBuffers) { ptr in
            for i in 0..<Int(bufferList.mNumberBuffers) {
                let buffer = UnsafeRawPointer(ptr).advanced(by: i * MemoryLayout<AudioBuffer>.stride)
                    .assumingMemoryBound(to: AudioBuffer.self).pointee
                totalChannels += Int(buffer.mNumberChannels)
            }
        }
        return totalChannels
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift build 2>&1`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git add Sources/VirtuMic/DeviceManager.swift
git commit -m "feat: add CoreAudio device enumeration and aggregate device creation"
```

---

### Task 5: Audio Daemon — AVAudioEngine Processing Chain

**Files:**
- Create: `Sources/VirtuMic/AudioDaemon.swift`

- [ ] **Step 1: Implement AudioDaemon.swift**

Create `Sources/VirtuMic/AudioDaemon.swift`:

```swift
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
        var lastFormat = inputFormat

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
            AudioUnitSetParameter(au, kDynamicsProcessorParam_MasterGain, kAudioUnitScope_Global, 0, config.compressor.masterGain, 0)

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
```

- [ ] **Step 2: Verify it builds**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift build 2>&1`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git add Sources/VirtuMic/AudioDaemon.swift
git commit -m "feat: add AudioDaemon with AVAudioEngine processing chain"
```

---

### Task 6: Main Entry Point — CLI + Signal Handling

**Files:**
- Modify: `Sources/VirtuMic/main.swift`

- [ ] **Step 1: Implement main.swift**

Replace `Sources/VirtuMic/main.swift` with:

```swift
import Foundation

// MARK: - Parse arguments

let configPath: String
if let configIdx = CommandLine.arguments.firstIndex(of: "--config"),
   configIdx + 1 < CommandLine.arguments.count {
    configPath = CommandLine.arguments[configIdx + 1]
} else {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    configPath = "\(home)/.config/virtual-mic/config.json"
}

// MARK: - Load and validate config

let config: AudioConfig
do {
    print("Loading config from: \(configPath)")
    config = try AudioConfig.load(from: configPath)
    try config.validate()
    print("Config loaded successfully.")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// MARK: - Start daemon

let daemon = AudioDaemon(config: config)

// MARK: - Signal handling for clean shutdown

let signalCallback: sig_t = { _ in
    daemon.stop()
    exit(0)
}
signal(SIGINT, signalCallback)
signal(SIGTERM, signalCallback)

do {
    try daemon.start()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Keep the process alive
dispatchMain()
```

- [ ] **Step 2: Verify it builds**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift build 2>&1`
Expected: Build Succeeded

- [ ] **Step 3: Run all tests**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test 2>&1`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git add Sources/VirtuMic/main.swift
git commit -m "feat: add main entry point with CLI arg parsing and signal handling"
```

---

### Task 7: Default Config + Install Script

**Files:**
- Create: `config/default-config.json`
- Create: `install.sh`

- [ ] **Step 1: Create default config**

Create `config/default-config.json`:

```json
{
  "inputDevice": "USB Microphone",
  "outputDevice": "BlackHole 2ch",
  "sampleRate": 48000,
  "noiseGate": {
    "enabled": true,
    "thresholdDB": -40.0,
    "attackTime": 0.002,
    "releaseTime": 0.05,
    "holdTime": 0.1
  },
  "eq": {
    "enabled": true,
    "globalGain": 0.0,
    "bands": [
      {
        "filterType": "highPass",
        "frequency": 80,
        "gain": 0,
        "bandwidth": 0.5
      },
      {
        "filterType": "parametric",
        "frequency": 200,
        "gain": -3,
        "bandwidth": 1.0
      },
      {
        "filterType": "parametric",
        "frequency": 3000,
        "gain": 3,
        "bandwidth": 1.5
      },
      {
        "filterType": "highShelf",
        "frequency": 10000,
        "gain": -2,
        "bandwidth": 0.5
      }
    ]
  },
  "compressor": {
    "enabled": true,
    "threshold": -20.0,
    "headRoom": 5.0,
    "attackTime": 0.01,
    "releaseTime": 0.1,
    "masterGain": 0.0
  }
}
```

- [ ] **Step 2: Create install.sh**

Create `install.sh`:

```bash
#!/bin/bash
set -euo pipefail

BINARY_NAME="virtual-mic-daemon"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/virtual-mic"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.virtumic.daemon.plist"

echo "=== VirtuMic Installer ==="

# Check for BlackHole
if ! system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole"; then
    echo ""
    echo "WARNING: BlackHole does not appear to be installed."
    echo "Install it with: brew install blackhole-2ch"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build
echo "Building release binary..."
swift build -c release

BINARY_PATH=".build/release/VirtuMic"
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Build failed, binary not found at $BINARY_PATH"
    exit 1
fi

# Install binary
echo "Installing binary to $INSTALL_DIR/$BINARY_NAME..."
sudo cp "$BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Install config (don't overwrite existing)
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    echo "Installing default config to $CONFIG_DIR/config.json..."
    cp config/default-config.json "$CONFIG_DIR/config.json"
    echo ""
    echo "IMPORTANT: Edit $CONFIG_DIR/config.json"
    echo "  Set 'inputDevice' to match your USB microphone name."
    echo "  Run: $INSTALL_DIR/$BINARY_NAME --list-devices to see available devices."
    echo ""
else
    echo "Config already exists at $CONFIG_DIR/config.json (not overwriting)"
fi

# Install LaunchAgent
echo "Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENT_DIR"
cat > "$LAUNCH_AGENT_DIR/$PLIST_NAME" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.virtumic.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$BINARY_NAME</string>
        <string>--config</string>
        <string>$CONFIG_DIR/config.json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/virtual-mic-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/virtual-mic-daemon.err</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
PLIST

# Load LaunchAgent
echo "Loading LaunchAgent..."
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_DIR/$PLIST_NAME"

echo ""
echo "=== Installation complete ==="
echo "VirtuMic is now running in the background."
echo ""
echo "In your meeting app, select 'BlackHole 2ch' as your microphone."
echo ""
echo "Useful commands:"
echo "  View logs:    tail -f /tmp/virtual-mic-daemon.log"
echo "  View errors:  tail -f /tmp/virtual-mic-daemon.err"
echo "  Stop:         launchctl bootout gui/$(id -u)/$PLIST_NAME"
echo "  Start:        launchctl bootstrap gui/$(id -u) $LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "  Edit config:  \$EDITOR $CONFIG_DIR/config.json"
echo "  After config change, restart with: launchctl kickstart -k gui/$(id -u)/com.virtumic.daemon"
```

- [ ] **Step 3: Make install.sh executable and verify build**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && chmod +x install.sh && swift build -c release 2>&1`
Expected: Build Succeeded

- [ ] **Step 4: Run all tests one final time**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift test 2>&1`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
cd "/Users/shaunz/Documents/Projects/Virtual Mic"
git add config/default-config.json install.sh
git commit -m "feat: add default config and install script with LaunchAgent setup"
```

---

### Task 8: Manual Integration Test

**Files:** None (testing only)

- [ ] **Step 1: Check BlackHole is installed**

Run: `brew list blackhole-2ch 2>&1 || echo "Not installed — run: brew install blackhole-2ch"`

- [ ] **Step 2: Identify your USB mic name**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift run VirtuMic --list-devices 2>&1`

Note: This won't work yet (we didn't add --list-devices). Instead, run the daemon and check the error output — it will print available device names if the configured name doesn't match.

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift run VirtuMic --config config/default-config.json 2>&1`

If the device name doesn't match, it will print available devices. Update `config/default-config.json` with the correct name.

- [ ] **Step 3: Run with correct config and verify audio flows**

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && swift run VirtuMic --config config/default-config.json 2>&1`
Expected: "VirtuMic is running. Audio chain: [your mic] -> processing -> BlackHole 2ch"

Open System Settings -> Sound -> Input and check that "BlackHole 2ch" shows audio levels when you speak into your USB mic.

- [ ] **Step 4: Test in a meeting app**

Open Google Meet (or Teams/Zoom) -> Settings -> Audio -> select "BlackHole 2ch" as microphone. Verify your voice comes through clearly.

- [ ] **Step 5: Stop the test run (Ctrl+C) and run the installer**

Press Ctrl+C to stop the test run, then:

Run: `cd "/Users/shaunz/Documents/Projects/Virtual Mic" && ./install.sh`

Verify the daemon starts automatically and audio flows.
