#!/bin/bash
set -euo pipefail

APP_NAME="VirtuMic"
BUNDLE_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "Building release binary..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"

# Copy binary
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VirtuMic</string>
    <key>CFBundleIdentifier</key>
    <string>com.virtumic.app2</string>
    <key>CFBundleName</key>
    <string>VirtuMic</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VirtuMic needs microphone access to process your audio for meetings.</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo ""
echo "App bundle created at: ${BUNDLE_DIR}"
echo ""
echo "To run:  open ${BUNDLE_DIR}"
echo "To install: cp -R ${BUNDLE_DIR} /Applications/"
