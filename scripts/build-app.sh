#!/bin/bash
# Builds ClaudeUsageMeter.app from the SwiftPM package (no Xcode needed),
# installs it to ~/Applications and launches it.
#
#   --no-install         only build build/ClaudeUsageMeter.app (used by the release workflow)
#   VERSION=1.2.3        override the version (default: 1.0.<commit count>, matching releases)
#   SWIFT_BUILD_FLAGS    extra `swift build` flags, e.g. "--arch arm64 --arch x86_64"
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageMeter"
BUNDLE_ID="com.local.claude-usage-meter"
APP="build/$APP_NAME.app"
DEST="$HOME/Applications/$APP_NAME.app"

INSTALL=1
[ "${1:-}" = "--no-install" ] && INSTALL=0

BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="${VERSION:-1.0.$BUILD}"

# shellcheck disable=SC2086  # SWIFT_BUILD_FLAGS is deliberately word-split
swift build -c release ${SWIFT_BUILD_FLAGS:-}
# shellcheck disable=SC2086
BIN="$(swift build -c release ${SWIFT_BUILD_FLAGS:-} --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Usage Meter</string>
  <key>CFBundleDisplayName</key><string>Claude Usage Meter</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"

[ "$INSTALL" -eq 1 ] || exit 0

pkill -x "$APP_NAME" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
