#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_EXECUTABLE="veil-host-shell"
BUNDLE_NAME="Veil"
BUNDLE_ID="org.uulab.veil.host-shell"
MIN_SYSTEM_VERSION="15.0"
BUNDLE_VERSION="$(date -u +%Y%m%d%H%M%S)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/mac-host"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$PACKAGE_DIR/VeilHostShell.entitlements"
APP_ICON="$APP_RESOURCES/VeilAppIcon.icns"

pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR" --product "$APP_EXECUTABLE"
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_EXECUTABLE"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
swift "$ROOT_DIR/script/generate_app_icon.swift" "$APP_ICON"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>VeilAppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>LSUIElement</key>
  <false/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BINARY" >/dev/null
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" --args "$@"
}

case "$MODE" in
  run)
    open_app
    ;;
  --start-vm|start-vm)
    open_app --start-vm
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..40}; do
      if pgrep -f "$APP_BINARY" >/dev/null; then
        break
      fi
      sleep 0.25
    done
    pgrep -f "$APP_BINARY" >/dev/null
    test -f "$APP_ICON"
    ;;
  *)
    echo "usage: $0 [run|--start-vm|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
