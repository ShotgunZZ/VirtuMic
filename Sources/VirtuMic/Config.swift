import Foundation
import AVFoundation

struct NoiseGateConfig: Codable {
    var enabled: Bool
    var thresholdDB: Float
    var attackTime: Float
    var releaseTime: Float
    var holdTime: Float
}

struct EQBandConfig: Codable {
    var filterType: String
    var frequency: Float
    var gain: Float
    var bandwidth: Float
}

struct EQConfig: Codable {
    var enabled: Bool
    var globalGain: Float
    var bands: [EQBandConfig]
}

struct CompressorConfig: Codable {
    var enabled: Bool
    var threshold: Float
    var headRoom: Float
    var attackTime: Float
    var releaseTime: Float
    var masterGain: Float
}

struct AudioConfig: Codable {
    var inputDevice: String
    var outputDevice: String
    var sampleRate: Double
    var noiseGate: NoiseGateConfig
    var eq: EQConfig
    var compressor: CompressorConfig

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
            guard !eq.bands.isEmpty else {
                throw ConfigError.outOfRange(
                    parameter: "eq.bands",
                    value: 0,
                    range: "at least 1 band required"
                )
            }
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

    static func filterTypeString(from type: AVAudioUnitEQFilterType) -> String {
        switch type {
        case .parametric: return "parametric"
        case .lowPass: return "lowPass"
        case .highPass: return "highPass"
        case .resonantLowPass: return "resonantLowPass"
        case .resonantHighPass: return "resonantHighPass"
        case .bandPass: return "bandPass"
        case .bandStop: return "bandStop"
        case .lowShelf: return "lowShelf"
        case .highShelf: return "highShelf"
        case .resonantLowShelf: return "resonantLowShelf"
        case .resonantHighShelf: return "resonantHighShelf"
        @unknown default: return "parametric"
        }
    }

    func save(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    static var defaultConfig: AudioConfig {
        AudioConfig(
            inputDevice: "fifine Microphone",
            outputDevice: "BlackHole 2ch",
            sampleRate: 44100,
            noiseGate: NoiseGateConfig(enabled: true, thresholdDB: -40, attackTime: 0.002, releaseTime: 0.05, holdTime: 0.1),
            eq: EQConfig(enabled: true, globalGain: 0, bands: [
                EQBandConfig(filterType: "highPass", frequency: 80, gain: 0, bandwidth: 0.5),
                EQBandConfig(filterType: "parametric", frequency: 200, gain: -3, bandwidth: 1.0),
                EQBandConfig(filterType: "parametric", frequency: 3000, gain: 3, bandwidth: 1.5),
                EQBandConfig(filterType: "highShelf", frequency: 10000, gain: -2, bandwidth: 0.5),
            ]),
            compressor: CompressorConfig(enabled: true, threshold: -20, headRoom: 5, attackTime: 0.01, releaseTime: 0.1, masterGain: 0)
        )
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
