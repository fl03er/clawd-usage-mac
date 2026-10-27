#!/bin/zsh
# Builds ClawdUsage.app next to this script.
#   ./build.sh           build for this Mac
#   ./build.sh install   build and copy to ~/Applications (needed for "start at login")
#   ./build.sh release   universal build (Apple Silicon + Intel) zipped into dist/
set -e
cd "$(dirname "$0")"
VERSION=0.6.0
APP=ClawdUsage.app
# Build and sign in a scratch folder, then copy: a synced folder (iCloud Desktop) gets File Provider attributes on
# the bundle while codesign runs, and codesign refuses a bundle with those.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
B="$STAGE/$APP"
mkdir -p "$B/Contents/MacOS" "$B/Contents/Resources/skins"
if [[ "$1" == "release" ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos13.0 -o "/tmp/ClawdUsage-$arch" Sources/*.swift -framework AppKit
  done
  lipo -create -output "$B/Contents/MacOS/ClawdUsage" /tmp/ClawdUsage-arm64 /tmp/ClawdUsage-x86_64
  rm -f /tmp/ClawdUsage-arm64 /tmp/ClawdUsage-x86_64
else
  # Same deployment target as the release build and LSMinimumSystemVersion; without it swiftc targets the SDK's
  # OS version, which Launch Services refuses (open, Login Items) when the Mac is on an older point release.
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" -o "$B/Contents/MacOS/ClawdUsage" Sources/*.swift -framework AppKit
fi
cp skins/*.txt "$B/Contents/Resources/skins/"
cat > "$B/Contents/Info.plist" <<PLIST
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
xattr -cr "$B"
codesign --force -s - "$B" || echo "warning: codesign failed"
rm -rf "$APP"
ditto "$B" "$APP"
echo "built $PWD/$APP"

if [[ "$1" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -f "ClawdUsage.app/Contents/MacOS/ClawdUsage" || true
  rm -rf ~/Applications/ClawdUsage.app
  ditto "$B" ~/Applications/ClawdUsage.app
  echo "installed ~/Applications/ClawdUsage.app"
fi

if [[ "$1" == "release" ]]; then
  mkdir -p dist
  rm -f "dist/ClawdUsage-$VERSION.zip"
  ditto -c -k --keepParent "$B" "dist/ClawdUsage-$VERSION.zip"
  lipo -archs "$B/Contents/MacOS/ClawdUsage"
  echo "packed $PWD/dist/ClawdUsage-$VERSION.zip"
fi
