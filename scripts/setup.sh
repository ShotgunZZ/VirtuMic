#!/bin/bash
# VirtuMic setup script — ensures BlackHole 2ch virtual audio driver is installed

set -e

BLACKHOLE_URL="https://existential.audio/blackhole/"

echo "Checking for BlackHole 2ch audio driver..."

# Check if BlackHole 2ch is already available as an audio device
if system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 2ch"; then
    echo "BlackHole 2ch is already installed."
    exit 0
fi

echo "BlackHole 2ch not found."

# Try installing via Homebrew if available
if command -v brew &>/dev/null; then
    echo "Installing BlackHole 2ch via Homebrew..."
    brew install blackhole-2ch
    echo "BlackHole 2ch installed successfully."
    echo "You may need to restart your Mac for the audio driver to appear."
    exit 0
fi

# No Homebrew — give manual instructions
echo ""
echo "Homebrew is not installed. Please install BlackHole 2ch manually:"
echo "  Download: $BLACKHOLE_URL"
echo ""
echo "Alternatively, install Homebrew first (https://brew.sh) then run:"
echo "  brew install blackhole-2ch"
exit 1
