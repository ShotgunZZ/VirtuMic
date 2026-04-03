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
                kAudioSubDeviceDriftCompensationKey as String: 0,
            ],
            [
                kAudioSubDeviceUIDKey as String: outputUID,
                kAudioSubDeviceDriftCompensationKey as String: 1,
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
