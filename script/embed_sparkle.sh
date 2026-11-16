#!/usr/bin/env bash
# Puts Sparkle.framework, which Veil updates itself with, into a staged Veil.app and signs it.
#
# usage: script/embed_sparkle.sh <Veil.app> <swift build bin path> <signing identity, or - for ad hoc>
#
# Run before the app binary and the bundle are signed: it adds the binary's Frameworks rpath, which
# changes the binary. Veil is not sandboxed, so Sparkle's XPC services are left out, as Sparkle's
# documentation allows (https://sparkle-project.org/documentation/sandboxing/); Autoupdate and
# Updater.app stay and are signed inside out, then the framework.
set -euo pipefail

APP_BUNDLE="$1"
BIN_PATH="$2"
IDENTITY="${3:--}"

SOURCE="$BIN_PATH/Sparkle.framework"
[[ -d "$SOURCE" ]] || { echo "embed_sparkle: no Sparkle.framework in $BIN_PATH" >&2; exit 2; }

FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"
FRAMEWORK="$FRAMEWORKS/Sparkle.framework"
BINARY="$APP_BUNDLE/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo veil-host-shell)"

mkdir -p "$FRAMEWORKS"
rm -rf "$FRAMEWORK"
ditto "$SOURCE" "$FRAMEWORK"
rm -rf "$FRAMEWORK/Versions/B/XPCServices" "$FRAMEWORK/XPCServices"

if ! otool -l "$BINARY" | grep -q "path @executable_path/../Frameworks "; then
  # Warns that the signature is now invalid; the caller signs the binary next.
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY" 2>/dev/null
fi

sign() {
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --options runtime --sign - "$@" >/dev/null
  else
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"
  fi
}

sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
