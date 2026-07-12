#!/bin/bash
# Builds Cleanium.app from the SPM release binary. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Cleanium.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Cleanium "$APP/Contents/MacOS/Cleanium"
# RuleEngine.loadBundledRules() looks up rules.json via Bundle.main first, which
# resolves the standard Contents/Resources location for a packaged .app — so we
# ship the plain resource there instead of relying on SwiftPM's Bundle.module bundle.
cp Sources/CleaniumCore/Resources/rules.json "$APP/Contents/Resources/rules.json"
# App icon (regenerate with: swift scripts/make-icon.swift)
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Cleanium</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.cleanium.app</string>
    <key>CFBundleName</key><string>Cleanium</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
