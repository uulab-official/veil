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
VERIFY_REPORT=""
VERIFY_KEEP_RUNNING=0

pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR" --product "$APP_EXECUTABLE"
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_EXECUTABLE"
# The program inside every Windows app launcher Veil writes to ~/Applications/Veil Apps.
swift build --package-path "$PACKAGE_DIR" --product veil-app-launcher
LAUNCHER_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/veil-app-launcher"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
mkdir -p "$APP_CONTENTS/Helpers"
cp "$LAUNCHER_BINARY" "$APP_CONTENTS/Helpers/veil-app-launcher"
chmod +x "$APP_CONTENTS/Helpers/veil-app-launcher"
swift "$ROOT_DIR/script/generate_app_icon.swift" "$APP_ICON"
# UI translations; SwiftUI looks string literals up in these Localizable.strings tables.
cp -R "$ROOT_DIR/apps/mac-host/Resources/"*.lproj "$APP_RESOURCES/"
# Shortcuts and Siri list Veil's App Intents only when the bundle carries Metadata.appintents, which
# `swift build` does not produce on its own. A development build still runs without it, so warn rather than stop.
"$ROOT_DIR/script/extract_app_intents_metadata.sh" debug "$BUILD_BINARY" "$APP_RESOURCES" \
  || echo "warning: Veil was built without App Intents metadata; its actions will not appear in Shortcuts." >&2

# Ship the Windows engine (QEMU, swtpm, Secure Boot firmware) inside the app. Bundling relinks and
# re-signs ~30 libraries, so the result is cached until the script or the source binaries change.
# Set VEIL_SKIP_ENGINE_BUNDLE=1 to build without it; Veil then looks for Homebrew's QEMU.
if [[ "${VEIL_SKIP_ENGINE_BUNDLE:-0}" != "1" ]]; then
  ENGINE_CACHE="$DIST_DIR/.engine-runtime"
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  engine_stamp="$(shasum "$ROOT_DIR/script/bundle_qemu_runtime.sh" "$ROOT_DIR/script/build_secure_firmware.sh" "$ROOT_DIR/script/build_patched_qemu.sh" "$ROOT_DIR"/script/qemu-patches/*.patch | cut -c1-16 | tr '\n' ' ')$(readlink -f "$brew_prefix/bin/qemu-system-aarch64" 2>/dev/null || true) $(readlink -f "$brew_prefix/bin/swtpm" 2>/dev/null || true)"
  if [[ "$(cat "$ENGINE_CACHE/.stamp" 2>/dev/null || true)" != "$engine_stamp" ]]; then
    if "$ROOT_DIR/script/bundle_qemu_runtime.sh" "$ENGINE_CACHE" >/dev/null; then
      echo "$engine_stamp" >"$ENGINE_CACHE/.stamp"
    else
      rm -rf "$ENGINE_CACHE"
      echo "warning: Veil was built without its Windows engine; it will look for Homebrew's QEMU instead." >&2
    fi
  fi
  if [[ -f "$ENGINE_CACHE/.stamp" ]]; then
    ditto "$ENGINE_CACHE" "$APP_RESOURCES/Runtime"
    rm -f "$APP_RESOURCES/Runtime/.stamp"
  fi
fi

# Ship the Windows guest tools so Veil installs and updates them without this repository.
# Without the .NET 8 SDK the app falls back to the repository's apps/windows-agent folder.
if [[ "${VEIL_SKIP_WINDOWS_AGENT_BUNDLE:-0}" != "1" ]]; then
  PATH="$HOME/.dotnet:$PATH" "$ROOT_DIR/script/bundle_windows_agent.sh" "$APP_RESOURCES" >/dev/null \
    || echo "warning: Veil was built without its Windows tools; install the .NET 8 SDK to bundle them." >&2
fi

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
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ko</string>
  </array>
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
  <!-- veil:// URLs; see docs/protocol.md "Mac Integration URLs". -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>org.uulab.veil.open</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>veil</string>
      </array>
    </dict>
  </array>
  <key>NSMicrophoneUsageDescription</key>
  <string>Windows apps in Veil can use your microphone, for example in calls or voice recording.</string>
</dict>
</plist>
PLIST

# A bundle copied from Downloads, AirDrop, or a quarantined workspace inherits
# com.apple.quarantine. With an ad-hoc local signature macOS reports that bundle
# as “damaged” instead of explaining that Gatekeeper blocked it. Clear only the
# quarantine marker before signing; do not remove any other extended attributes.
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

codesign --force --sign - "$APP_CONTENTS/Helpers/veil-app-launcher" >/dev/null
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BINARY" >/dev/null
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null

open_app() {
  # VEIL_LAUNCH_IN_BACKGROUND=1 relaunches without taking the Mac over: no activation, windows behind.
  if [[ "${VEIL_LAUNCH_IN_BACKGROUND:-0}" == "1" ]]; then
    /usr/bin/open -g -n "$APP_BUNDLE" --args -VeilLaunchInBackground "$@"
    return
  fi
  /usr/bin/open -n "$APP_BUNDLE" --args "$@"
}

wait_for_app_process() {
  local attempts=40
  for ((i = 1; i <= attempts; i++)); do
    if pgrep -x "$APP_EXECUTABLE" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  echo "Veil did not launch a running $APP_EXECUTABLE process within $((attempts / 4)) seconds." >&2
  return 1
}

wait_for_launch_report() {
  local report_path="$1"
  local attempts=40
  for ((i = 1; i <= attempts; i++)); do
    if [[ -s "$report_path" ]]; then
      return 0
    fi
    sleep 0.25
  done

  echo "Veil launched, but no main-window verification report was written within $((attempts / 4)) seconds." >&2
  return 1
}

launch_report_value() {
  local report_path="$1"
  local key="$2"
  plutil -extract "$key" raw -o - "$report_path"
}

verify_launch_report() {
  local report_path="$1"
  plutil -lint "$report_path" >/dev/null

  local bundle_identifier
  bundle_identifier="$(launch_report_value "$report_path" bundleIdentifier)"
  local meets_contract
  meets_contract="$(launch_report_value "$report_path" meetsLauncherContract)"
  local expected_bundle_id="${VEIL_VERIFY_EXPECT_BUNDLE_ID:-$BUNDLE_ID}"

  if [[ "$bundle_identifier" != "$expected_bundle_id" || ( "$meets_contract" != "true" && "$meets_contract" != "1" ) ]]; then
    echo "Veil launch report did not satisfy the one-window app contract:" >&2
    cat "$report_path" >&2
    return 1
  fi
}

stop_app_process() {
  pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true

  local attempts=20
  for ((i = 1; i <= attempts; i++)); do
    if ! pgrep -x "$APP_EXECUTABLE" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  echo "Veil launched, but $APP_EXECUTABLE did not exit after verification cleanup." >&2
  return 1
}

cleanup_verify() {
  local status=$?

  if [[ -n "${VERIFY_REPORT:-}" ]]; then
    if [[ "$status" -eq 0 ]]; then
      rm -f "$VERIFY_REPORT"
    elif [[ -s "$VERIFY_REPORT" ]]; then
      local preserved_report="$DIST_DIR/veil-launch-report-failed-$(date -u +%Y%m%d%H%M%S).plist"
      cp "$VERIFY_REPORT" "$preserved_report"
      echo "Veil launch verification report preserved at $preserved_report" >&2
      rm -f "$VERIFY_REPORT"
    else
      rm -f "$VERIFY_REPORT"
    fi
  fi

  if [[ "$status" -ne 0 || "$VERIFY_KEEP_RUNNING" -eq 0 ]]; then
    pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
  fi

  exit "$status"
}

case "$MODE" in
  --build-only|build-only)
    ;;
  run)
    open_app
    ;;
  --start-vm|start-vm)
    open_app --start-vm
    ;;
  --demo|demo)
    open_app --demo
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
  --verify|verify|--verify-keep-running|verify-keep-running)
    trap cleanup_verify EXIT
    codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null
    plutil -lint "$INFO_PLIST" >/dev/null
    test -f "$APP_ICON"
    if [[ "$MODE" == "--verify-keep-running" || "$MODE" == "verify-keep-running" ]]; then
      VERIFY_KEEP_RUNNING=1
    fi
    VERIFY_REPORT="$(mktemp -t veil-launch-report.XXXXXX.plist)"
    rm -f "$VERIFY_REPORT"
    open_app --launch-verification-report "$VERIFY_REPORT"
    wait_for_app_process
    wait_for_launch_report "$VERIFY_REPORT"
    verify_launch_report "$VERIFY_REPORT"
    cp "$VERIFY_REPORT" "$DIST_DIR/veil-launch-report-latest.plist"
    if [[ "$VERIFY_KEEP_RUNNING" -eq 0 ]]; then
      stop_app_process
    fi
    exit 0
    ;;
  *)
    echo "usage: $0 [--build-only|run|--start-vm|--demo|--debug|--logs|--telemetry|--verify|--verify-keep-running]" >&2
    exit 2
    ;;
esac
