#!/bin/zsh
# Builds ClawdUsage.app next to this script.
set -e
cd "$(dirname "$0")"
APP=ClawdUsage.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/skins"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/ClawdUsage" Sources/*.swift -framework AppKit
cp skins/*.txt "$APP/Contents/Resources/skins/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clawd Usage</string>
  <key>CFBundleIdentifier</key><string>local.clawd-usage-mac</string>
  <key>CFBundleExecutable</key><string>ClawdUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "built $PWD/$APP"

# ./build.sh install - copy to ~/Applications (needed for "로그인 시 자동 실행").
if [[ "$1" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -f "ClawdUsage.app/Contents/MacOS/ClawdUsage" || true
  rm -rf ~/Applications/ClawdUsage.app
  cp -R "$APP" ~/Applications/
  echo "installed ~/Applications/ClawdUsage.app"
fi
