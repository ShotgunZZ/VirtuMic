# VirtuMic Design Spec

**Date:** 2026-04-02
**Status:** Approved

## Overview

VirtuMic is a lightweight macOS audio processing daemon that sits between a USB microphone and BlackHole (virtual audio driver), applying EQ, compression, and noise gating. Meeting apps select BlackHole as their microphone input and receive studio-quality processed audio.

## Architecture

```
USB Mic (hardware)
    |
    v
[Private Aggregate Device] (combines USB mic input + BlackHole output)
    |
    v
AVAudioEngine
    |
    v
inputNode -> NoiseGate -> EQ (AVAudioUnitEQ) -> Compressor (AUDynamicsProcessor) -> outputNode
    |                                                                                    |
    v                                                                                    v
 USB Mic                                                                          BlackHole 2ch
    ^
    |
config.json (read at launch)
```

Meeting apps select "BlackHole 2ch" as their microphone.

## Components

### 1. Audio Daemon (`virtual-mic-daemon`)

A Swift command-line binary. No UI, no menu bar. Runs as a background process.

**Responsibilities:**
- Enumerate audio devices via CoreAudio to find the configured input (USB mic) and output (BlackHole) by name
- Create a private aggregate device combining both devices, with the USB mic as clock master and drift compensation enabled on BlackHole
- Build an AVAudioEngine processing chain: `inputNode -> NoiseGate -> EQ -> Compressor -> outputNode`
- Load all DSP parameters from `~/.config/virtual-mic/config.json` at startup
- Run indefinitely via `dispatchMain()`
- Handle USB mic disconnection: detect via `kAudioDevicePropertyDeviceIsAlive` listener, stop engine, wait for reconnection, restart
- Clean up aggregate device on exit via `AudioHardwareDestroyAggregateDevice()`

**Processing chain order:**
1. **Noise Gate** (first) — silence background noise before it hits EQ/compressor
2. **EQ** (second) — shape the tone
3. **Compressor** (third) — even out dynamics on the shaped signal

### 2. Noise Gate (Custom AUAudioUnit)

macOS has no built-in noise gate Audio Unit. We implement a minimal custom `AUAudioUnit` subclass.

**Parameters:**
| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| thresholdDB | Float | -40.0 | -96...0 | Signal level below which gate closes (dB) |
| attackTime | Float | 0.002 | 0.0001...0.1 | Time to open gate (seconds) |
| releaseTime | Float | 0.05 | 0.01...1.0 | Time to close gate (seconds) |
| holdTime | Float | 0.1 | 0.0...2.0 | Time gate stays open after signal drops below threshold (seconds) |

**DSP logic:**
- Track input signal level (absolute value of samples)
- When level >= threshold (linear): reset hold counter
- While hold counter > 0: gate is open, decrement counter each sample
- Envelope follower smooths transitions: attack coefficient when opening, release coefficient when closing
- Multiply each sample by envelope value (0.0 = silent, 1.0 = full pass)

**Implementation:** Custom `AUAudioUnit` subclass registered via `AUAudioUnit.registerSubclass()`, wrapped in `AVAudioUnitEffect` for integration with AVAudioEngine's node graph.

### 3. EQ (AVAudioUnitEQ)

Uses Apple's built-in `AVAudioUnitEQ` which wraps the `AUNBandEQ` Audio Unit. Supports up to 16 bands.

**Default preset (USB mic for meetings):**

| Band | Filter Type | Frequency | Gain | Bandwidth | Purpose |
|------|------------|-----------|------|-----------|---------|
| 0 | highPass | 80 Hz | 0 dB | 0.5 oct | Cut rumble, handling noise, HVAC |
| 1 | parametric | 200 Hz | -3 dB | 1.0 oct | Reduce muddiness/boominess |
| 2 | parametric | 3000 Hz | +3 dB | 1.5 oct | Presence boost for speech clarity |
| 3 | highShelf | 10000 Hz | -2 dB | 0.5 oct | Tame harshness from cheap USB mic capsule |

**Supported filter types** (mapped from config string to `AVAudioUnitEQFilterType`):
- `parametric`, `lowPass`, `highPass`, `resonantLowPass`, `resonantHighPass`
- `bandPass`, `bandStop`, `lowShelf`, `highShelf`, `resonantLowShelf`, `resonantHighShelf`

**Important:** Each band's `bypass` defaults to `true` in AVAudioUnitEQ. Must explicitly set `bypass = false` for every active band.

### 4. Compressor (AUDynamicsProcessor)

Uses Apple's built-in `AUDynamicsProcessor` loaded via `AVAudioUnitEffect`.

**Parameters:**

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| threshold | -20.0 dB | -40...20 | Level above which compression starts |
| headRoom | 5.0 dB | 0.1...40 | dB above threshold before hard limiting |
| attackTime | 0.01 s | 0.0001...0.2 | How fast compressor reacts to loud signal |
| releaseTime | 0.1 s | 0.01...3.0 | How fast compressor releases after signal drops |
| masterGain | 0.0 dB | -40...40 | Makeup gain after compression |

Set via `AudioUnitSetParameter()` on the underlying `AudioUnit` reference.

### 5. Config File

**Location:** `~/.config/virtual-mic/config.json`

**Full schema:**

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
      { "filterType": "highPass", "frequency": 80, "gain": 0, "bandwidth": 0.5 },
      { "filterType": "parametric", "frequency": 200, "gain": -3, "bandwidth": 1.0 },
      { "filterType": "parametric", "frequency": 3000, "gain": 3, "bandwidth": 1.5 },
      { "filterType": "highShelf", "frequency": 10000, "gain": -2, "bandwidth": 0.5 }
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

**Device matching:** `inputDevice` and `outputDevice` are matched by substring against CoreAudio device names. The first match is used.

**Validation at load time:**
- Frequencies must be 20...sampleRate/2
- Gains must be -96...24
- Time values must be within the ranges specified in parameter tables above
- At least one EQ band required if EQ is enabled
- Exit with clear error message if validation fails

**Decoded via:** Swift `Codable` protocol with `JSONDecoder`.

### 6. Aggregate Device

Created programmatically at runtime via `AudioHardwareCreateAggregateDevice()`.

**Configuration:**
- Name: `"VirtuMicAggregate"`
- UID: `"com.virtumic.aggregate"`
- Master sub-device: USB mic UID (real hardware clock source)
- Drift compensation: enabled on BlackHole (virtual device, no real clock)
- Private: `true` (hidden from Audio MIDI Setup, though macOS may still show it)

**Lifecycle:**
- Created on daemon start
- Destroyed on daemon exit (SIGTERM/SIGINT handler + `AudioHardwareDestroyAggregateDevice()`)
- Recreated if USB mic disconnects and reconnects

### 7. LaunchAgent

**Plist:** `~/Library/LaunchAgents/com.virtumic.daemon.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.virtumic.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/virtual-mic-daemon</string>
        <string>--config</string>
        <string>/Users/shaunz/.config/virtual-mic/config.json</string>
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
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Config file not found | Exit with error message and path to expected location |
| Config validation fails | Exit with specific error (which parameter, what range) |
| Input device not found | Print available devices, exit with error |
| Output device not found (BlackHole not installed) | Print instructions to install BlackHole, exit |
| Aggregate device creation fails | Exit with CoreAudio error code |
| USB mic disconnected while running | Stop engine, log message, poll for device every 5 seconds, restart when found |
| Engine start fails | Exit with error (launchd will restart via KeepAlive) |

## Project Structure

```
Virtual Mic/
  Package.swift
  Sources/
    VirtuMic/
      main.swift              -- entry point, signal handlers, dispatchMain()
      AudioDaemon.swift       -- engine setup, aggregate device, processing chain
      DeviceManager.swift     -- CoreAudio device enumeration, aggregate creation
      NoiseGate.swift         -- custom AUAudioUnit subclass + DSP render block
      Config.swift            -- Codable structs, JSON loading, validation
  config/
    default-config.json       -- example config with defaults
  install.sh                  -- build + install binary + LaunchAgent plist
```

## Dependencies

- **Runtime:** macOS 13+ (Ventura), AVFoundation, CoreAudio, Accelerate frameworks. No third-party dependencies.
- **Build:** Swift Package Manager (`swift build -c release`)
- **External:** BlackHole 2ch must be installed (`brew install blackhole-2ch`)

## Testing Strategy

- **Manual testing:** Build and run, verify audio passes through to BlackHole with processing applied. Use Audio MIDI Setup or a DAW to monitor BlackHole input.
- **Config testing:** Validate that malformed JSON, missing fields, and out-of-range values produce clear error messages.
- **Device testing:** Unplug USB mic while running, verify daemon recovers when mic is reconnected.
- **Meeting testing:** Select BlackHole 2ch in Google Meet/Teams/Zoom, verify audio quality.

## Out of Scope

- GUI / menu bar app
- Live config reloading (restart daemon to apply changes)
- Multiple microphone support
- Audio recording/monitoring
- Windows/Linux support
