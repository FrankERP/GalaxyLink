#!/bin/bash
# Assemble a double-clickable GalaxyLink.app from the release build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/GalaxyLink.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/GalaxyLink "$APP/Contents/MacOS/"
# Bundle.module finds the resource bundle via Bundle.main.resourceURL.
cp -R .build/release/GalaxyLink_GalaxyLink.bundle "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.frankrocha.galaxylink</string>
    <key>CFBundleName</key>
    <string>GalaxyLink</string>
    <key>CFBundleExecutable</key>
    <string>GalaxyLink</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>GalaxyLink captures a virtual display to stream it as a second screen to your tablet.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: gives the app a stable identity so the Screen Recording
# permission survives rebuilds.
codesign --force --sign - "$APP"

echo "Built $APP"
