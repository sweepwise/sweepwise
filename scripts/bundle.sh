#!/bin/bash
# Builds Sweepwise.app from the SPM release binary. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary: Apple Silicon + Intel in one executable.
swift build -c release --arch arm64 --arch x86_64

APP=dist/Sweepwise.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Multi-arch builds land in .build/apple/Products/Release.
cp .build/apple/Products/Release/Sweepwise "$APP/Contents/MacOS/Sweepwise"
# RuleEngine.loadBundledRules() looks up rules.json via Bundle.main first, which
# resolves the standard Contents/Resources location for a packaged .app — so we
# ship the plain resource there instead of relying on SwiftPM's Bundle.module bundle.
cp Sources/SweepwiseCore/Resources/rules.json "$APP/Contents/Resources/rules.json"
# App icon (regenerate with: swift scripts/make-icon.swift)
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Sweepwise</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.sweepwise.app</string>
    <key>CFBundleName</key><string>Sweepwise</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.4</string>
    <key>CFBundleVersion</key><string>0.1.4</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Signing:
#   default            -> ad-hoc signature (local use; needs right-click→Open once)
#   SWEEPWISE_SIGN_IDENTITY set to a "Developer ID Application: … (TEAMID)" identity
#                      -> hardened-runtime signature required for notarization
if [[ -n "${SWEEPWISE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --sign "$SWEEPWISE_SIGN_IDENTITY" "$APP"
  echo "Built $APP (signed: $SWEEPWISE_SIGN_IDENTITY)"
else
  codesign --force --sign - "$APP"
  echo "Built $APP (ad-hoc signed)"
fi
