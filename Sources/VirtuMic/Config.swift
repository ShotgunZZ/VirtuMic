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
