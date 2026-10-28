#!/bin/bash
# Builds a release "Claude Code Herder.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app="Claude Code Herder.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClaudeHerder" "$app/Contents/MacOS/"

# The icon is drawn in code (Icon/draw_icon.swift), then scaled into an .icns.
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
swift Icon/draw_icon.swift "$iconset/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Code Herder</string>
    <key>CFBundleIdentifier</key><string>com.tomcc.claude-herder</string>
    <key>CFBundleExecutable</key><string>ClaudeHerder</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Claude Code Herder opens sessions in new Ghostty tabs.</string>
</dict>
</plist>
PLIST
# Ad-hoc signature: enough to run locally and to remember the Automation permission.
codesign --force --sign - "$app"
echo "Built $(pwd)/$app"
