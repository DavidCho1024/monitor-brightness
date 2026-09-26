#!/bin/bash
# Builds "Monitor Brightness.app" into ~/Applications and starts it.
# Requires Xcode Command Line Tools:  xcode-select --install
set -e
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Run:  xcode-select --install   then run this script again."
  exit 1
fi

APP="$HOME/Applications/Monitor Brightness.app"
osascript -e 'quit app "Monitor Brightness"' >/dev/null 2>&1 || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building..."
swiftc -O MonitorBrightness.swift -o "$APP/Contents/MacOS/MonitorBrightness" \
  -framework Cocoa -framework AVFoundation -framework ServiceManagement

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Monitor Brightness</string>
  <key>CFBundleDisplayName</key><string>Monitor Brightness</string>
  <key>CFBundleIdentifier</key><string>app.pixelbrightness.monitor</string>
  <key>CFBundleExecutable</key><string>MonitorBrightness</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS lets it run locally
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

echo "Installed: $APP"

# Offer to keep it in the Dock (skipped if it's already there)
if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "Monitor%20Brightness.app\|Monitor Brightness.app"; then
  if [[ "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)" == *ko* ]]; then Q="Dock에 고정할까요? [Y/n] "; else Q="Keep Monitor Brightness in the Dock? [Y/n] "; fi
  read -r -p "$Q" ans
  if [[ -z "$ans" || "$ans" =~ ^[Yy] ]]; then
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock
  fi
fi

open "$APP"
