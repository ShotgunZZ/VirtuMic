# VirtuMic

Open-source virtual microphone for macOS with built-in noise gate, EQ, and compressor.

VirtuMic routes audio from any input device through a real-time processing chain — noise gate, 5-band parametric EQ, and compressor — then outputs to a virtual audio device ([BlackHole](https://existential.audio/blackhole/)). Any app (Zoom, Discord, OBS, etc.) can use BlackHole as its microphone input to get your processed audio.

## Requirements

- macOS 13 (Ventura) or later
- [BlackHole 2ch](https://existential.audio/blackhole/) virtual audio driver

## Install

```bash
brew tap ShotgunZZ/tap
brew install --cask virtumic
```

BlackHole 2ch will be installed automatically if not already present.

## Usage

1. **Launch VirtuMic** — it appears as a microphone icon in your menu bar
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
- **Low latency** — lock-free ring buffer with 512-frame I/O buffers (~10ms)
- **Persistent config** — settings saved automatically to `~/.config/virtual-mic/config.json`

## Known Limitations

- **Bluetooth input devices** (AirPods, etc.) may not work reliably due to Bluetooth audio profile switching
- **Unsigned app** — macOS Gatekeeper will warn on first launch. Right-click the app → Open to bypass this once

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
