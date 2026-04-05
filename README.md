# VirtuMic

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black.svg)](https://github.com/ShotgunZZ/VirtuMic)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)

Open-source virtual microphone for macOS with built-in noise gate, EQ, and compressor.

VirtuMic routes audio from any input device through a real-time processing chain — noise gate, 5-band parametric EQ, and compressor — then outputs to a virtual audio device ([BlackHole](https://existential.audio/blackhole/)). Any app (Zoom, Discord, OBS, etc.) can use BlackHole as its microphone input to get your processed audio.

## How It Works

```
Microphone → Noise Gate → EQ → Compressor → BlackHole → Zoom/Discord/OBS
```

VirtuMic runs two audio engines connected by a lock-free ring buffer. The input engine captures and processes your mic audio in real time. The output engine writes the processed audio to BlackHole, which appears as a virtual microphone to other apps.

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac
- [BlackHole 2ch](https://existential.audio/blackhole/) virtual audio driver

## Install

```bash
brew tap ShotgunZZ/tap
brew install --cask virtumic
```

BlackHole 2ch will be installed automatically if not already present.

## Usage

1. **Launch VirtuMic** — it appears as a cyan microphone icon in your menu bar
2. **Click the icon** → **Show Mixer** to open the audio controls
3. **Select your input device** (microphone, headset, etc.) from the dropdown
4. **Adjust processing** — tune the noise gate, EQ bands, and compressor to taste
5. **In your app** (Zoom, Discord, etc.), set the input/microphone to **"BlackHole 2ch"**

Your voice now goes through VirtuMic's processing chain before reaching the other app.

### Monitoring

Click **Monitor (Speakers)** in the menu bar to hear your processed audio through your output device. This lets you hear exactly what others will hear.

## Features

- **Noise Gate** — cuts background noise when you're not speaking (adjustable threshold, attack, hold, release)
- **5-Band Parametric EQ** — shape your tone with low shelf, 3 parametric bands, and high shelf
- **Compressor** — even out volume levels (threshold, headroom, attack, release, gain)
- **Real-time level meter** — see your input level at a glance
- **Low latency** — lock-free ring buffer with 512-frame I/O buffers
- **Persistent config** — settings saved automatically to `~/.config/virtual-mic/config.json`

## Configuration

Settings are stored at `~/.config/virtual-mic/config.json` and saved automatically when you adjust controls. The config persists across app updates and reinstalls.

## Known Limitations

- **Bluetooth input devices** (AirPods, etc.) may not work reliably due to Bluetooth audio profile switching
- **ARM only** — Homebrew releases are built for Apple Silicon. Intel users can build from source.

## Troubleshooting

**"VirtuMic is damaged and can't be opened"**
The app is unsigned. Run: `xattr -cr /Applications/VirtuMic.app`

**No menu bar icon appears**
Try quitting and relaunching. If it persists, reset Launch Services:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/VirtuMic.app
```

**Microphone permission denied**
Go to System Settings → Privacy & Security → Microphone and enable VirtuMic.

**No audio output**
Make sure the app you're using (Zoom, Discord, etc.) has its input set to "BlackHole 2ch", not your physical microphone.

**Audio dropouts or glitches**
Close other audio-intensive apps. If using a USB microphone, try a different USB port.

## Building from Source

```bash
git clone https://github.com/ShotgunZZ/VirtuMic.git
cd VirtuMic
swift build
.build/debug/VirtuMic
```

For a release build:

```bash
swift build -c release
.build/release/VirtuMic
```

## License

[MIT](LICENSE)
