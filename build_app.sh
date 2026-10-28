#!/bin/bash
# Builds a release ClaudeHerder.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=ClaudeHerder.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/ClaudeHerder" "$app/Contents/MacOS/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Herder</string>
    <key>CFBundleIdentifier</key><string>com.tomcc.claude-herder</string>
    <key>CFBundleExecutable</key><string>ClaudeHerder</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Claude Herder opens sessions in new Ghostty tabs.</string>
</dict>
</plist>
PLIST
# Ad-hoc signature: enough to run locally and to remember the Automation permission.
codesign --force --sign - "$app"
echo "Built $(pwd)/$app"
