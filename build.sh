#!/bin/zsh
# Builds ClawdUsage.app next to this script.
#   ./build.sh           build for this Mac
#   ./build.sh install   build and copy to ~/Applications (needed for "start at login")
#   ./build.sh release   universal build (Apple Silicon + Intel) zipped into dist/
set -e
cd "$(dirname "$0")"
VERSION=0.5.0
APP=ClawdUsage.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/skins"
if [[ "$1" == "release" ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos13.0 -o "/tmp/ClawdUsage-$arch" Sources/*.swift -framework AppKit
  done
  lipo -create -output "$APP/Contents/MacOS/ClawdUsage" /tmp/ClawdUsage-arm64 /tmp/ClawdUsage-x86_64
  rm -f /tmp/ClawdUsage-arm64 /tmp/ClawdUsage-x86_64
else
  swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/ClawdUsage" Sources/*.swift -framework AppKit
fi
cp skins/*.txt "$APP/Contents/Resources/skins/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clawd Usage</string>
  <key>CFBundleIdentifier</key><string>local.clawd-usage-mac</string>
  <key>CFBundleExecutable</key><string>ClawdUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# Ad-hoc signature; extended attributes on the files would make codesign refuse.
xattr -cr "$APP"
codesign --force -s - "$APP" || echo "warning: codesign failed"
echo "built $PWD/$APP"

if [[ "$1" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -f "ClawdUsage.app/Contents/MacOS/ClawdUsage" || true
  rm -rf ~/Applications/ClawdUsage.app
  cp -R "$APP" ~/Applications/
  echo "installed ~/Applications/ClawdUsage.app"
fi

if [[ "$1" == "release" ]]; then
  mkdir -p dist
  rm -f "dist/ClawdUsage-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "dist/ClawdUsage-$VERSION.zip"
  lipo -archs "$APP/Contents/MacOS/ClawdUsage"
  echo "packed $PWD/dist/ClawdUsage-$VERSION.zip"
fi
