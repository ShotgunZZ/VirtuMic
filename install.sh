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
launchctl bootout "gui/$(id -u)/com.virtumic.daemon" 2>/dev/null || true
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
echo "  Stop:         launchctl bootout gui/\$(id -u)/$PLIST_NAME"
echo "  Start:        launchctl bootstrap gui/\$(id -u) $LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "  Edit config:  \$EDITOR $CONFIG_DIR/config.json"
echo "  After config change, restart with: launchctl kickstart -k gui/\$(id -u)/com.virtumic.daemon"
