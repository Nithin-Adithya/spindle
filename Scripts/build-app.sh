#!/bin/bash
# Builds Spindle.app into ./build using only the Command Line Tools (no Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Spindle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Spindle" "$APP/Contents/MacOS/Spindle"

# Translations: Localization/<language>.txt holds one line per line of keys.txt.
mkdir -p "$APP/Contents/Resources"
python3 Scripts/make-strings.py Localization "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleAllowMixedLocalizations</key><true/>
    <key>CFBundleExecutable</key><string>Spindle</string>
    <key>CFBundleIdentifier</key><string>com.nithinadithya.spindle</string>
    <key>CFBundleName</key><string>Spindle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Spindle reads the current track from Music and Spotify and controls playback.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
