#!/bin/bash
# Sweepwise installer. Downloads the latest release, installs it to
# /Applications, and offers to open it at login.
#
#   curl -fsSL https://sweepwise.app/install.sh | bash
#
set -euo pipefail

REPO="sweepwise/sweepwise"
APP="Sweepwise.app"
DEST="/Applications/$APP"
ZIP_URL="https://github.com/$REPO/releases/latest/download/Sweepwise.zip"

say() { printf "\033[1;32m→\033[0m %s\n" "$1"; }

# Read prompts from the terminal even when the script itself arrives on stdin
# (the `curl | bash` case, where stdin is the script, not the keyboard).
ask() {
  local prompt="$1" reply
  if [ -r /dev/tty ]; then read -r -p "$prompt" reply </dev/tty; else reply="n"; fi
  printf '%s' "$reply"
}

[ "$(uname)" = "Darwin" ] || { echo "Sweepwise is macOS only."; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading the latest release…"
curl -fSL --progress-bar "$ZIP_URL" -o "$TMP/Sweepwise.zip"

say "Unpacking…"
ditto -x -k "$TMP/Sweepwise.zip" "$TMP"
[ -d "$TMP/$APP" ] || { echo "Unexpected archive layout — $APP not found."; exit 1; }

# Quit a running copy before replacing it.
if pgrep -f "$APP/Contents/MacOS/Sweepwise" >/dev/null 2>&1; then
  say "Quitting the running copy…"
  osascript -e 'quit app "Sweepwise"' 2>/dev/null || pkill -f "$APP/Contents/MacOS/Sweepwise" || true
  sleep 1
fi

say "Moving to /Applications…"
rm -rf "$DEST"
mv "$TMP/$APP" "$DEST"

# Releases are notarized since v0.1.4, so this is now just a belt-and-braces
# cleanup; it also keeps installs of older releases working.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Set the app to launch at login. First try a real Login Item (shows in
# System Settings → Login Items). That path asks macOS for permission to
# control System Events the first time; if it's denied or unavailable, fall
# back to a LaunchAgent, which needs no prompt and still opens the app at login.
setup_login() {
  osascript -e 'tell application "System Events" to delete login item "Sweepwise"' 2>/dev/null || true
  if osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$DEST\", hidden:false}" >/dev/null 2>&1; then
    say "Added to Login Items (System Settings → General → Login Items)."
    return
  fi
  local plist="$HOME/Library/LaunchAgents/com.sweepwise.app.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.sweepwise.app</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/Sweepwise</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PL
  say "Set to open at login. Turn off anytime: rm \"$plist\""
}

case "$(ask 'Open Sweepwise automatically when you log in? [y/N] ')" in
  [yY]*) setup_login ;;
  *)     say "Skipped. Add it anytime in System Settings → General → Login Items." ;;
esac

say "Launching Sweepwise…"
open "$DEST"
echo
echo "Installed. Look for the disk icon in your menu bar (top-right)."
echo "Uninstall later with:  rm -rf \"$DEST\""
