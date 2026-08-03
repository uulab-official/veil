#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0

if [[ "${1:-}" == "--skip-build" ]]; then
  SKIP_BUILD=1
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "usage: ./script/test_macos_lifecycle.sh [--skip-build]" >&2
  exit 2
fi

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/veil-app-lifecycle.XXXXXX")"
APPLICATIONS_DIR="$TEST_ROOT/Applications"
TRASH_DIR="$TEST_ROOT/Trash"
SUPPORT_SENTINEL="$TEST_ROOT/Application Support/Veil/preserve-me.txt"
INSTALLED_APP="$APPLICATIONS_DIR/Veil.app"
FOREIGN_APP="$APPLICATIONS_DIR/Foreign.app"
LAUNCH_REPORT="$TEST_ROOT/installed-launch-report.plist"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  "$ROOT_DIR/script/build_and_run.sh" --build-only
fi

mkdir -p "$(dirname "$SUPPORT_SENTINEL")"
printf 'preserve user state\n' >"$SUPPORT_SENTINEL"

"$ROOT_DIR/script/install_macos.sh" --destination "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$INSTALLED_APP/Contents/Info.plist")" == "org.uulab.veil.host-shell" ]]

if "$ROOT_DIR/script/install_macos.sh" --destination "$INSTALLED_APP" >/dev/null 2>&1; then
  echo "Installer overwrote an existing app without --replace." >&2
  exit 1
fi

"$ROOT_DIR/script/install_macos.sh" --destination "$INSTALLED_APP" --replace

ditto "$INSTALLED_APP" "$FOREIGN_APP"
plutil -replace CFBundleIdentifier -string com.example.foreign "$FOREIGN_APP/Contents/Info.plist"
if "$ROOT_DIR/script/install_macos.sh" --destination "$FOREIGN_APP" --replace >/dev/null 2>&1; then
  echo "Installer replaced a foreign app bundle." >&2
  exit 1
fi
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$FOREIGN_APP/Contents/Info.plist")" == "com.example.foreign" ]] || {
  echo "Installer modified a foreign app bundle before refusing it." >&2
  exit 1
}

"$ROOT_DIR/script/uninstall_macos.sh" --destination "$INSTALLED_APP" --trash-directory "$TRASH_DIR"

[[ ! -e "$INSTALLED_APP" ]] || { echo "Uninstall left the app in place." >&2; exit 1; }
[[ -f "$SUPPORT_SENTINEL" ]] || { echo "Uninstall removed support data." >&2; exit 1; }
[[ -d "$TRASH_DIR/Veil.app" ]] || { echo "Uninstall did not leave a recoverable app in Trash." >&2; exit 1; }

"$ROOT_DIR/script/install_macos.sh" --destination "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
[[ -f "$SUPPORT_SENTINEL" ]] || { echo "Reinstall did not preserve support data." >&2; exit 1; }

mkdir -p "$TEST_ROOT/Home"
CFFIXED_USER_HOME="$TEST_ROOT/Home" HOME="$TEST_ROOT/Home" \
  "$INSTALLED_APP/Contents/MacOS/veil-host-shell" --launch-verification-report "$LAUNCH_REPORT" \
  >/dev/null 2>&1 &
APP_PID=$!

for ((attempt = 1; attempt <= 40; attempt++)); do
  [[ -s "$LAUNCH_REPORT" ]] && break
  kill -0 "$APP_PID" >/dev/null 2>&1 || {
    echo "Reinstalled Veil exited before writing its launch report." >&2
    exit 1
  }
  sleep 0.25
done

[[ -s "$LAUNCH_REPORT" ]] || { echo "Reinstalled Veil did not write a launch report." >&2; exit 1; }
plutil -lint "$LAUNCH_REPORT" >/dev/null
[[ "$(plutil -extract bundleIdentifier raw -o - "$LAUNCH_REPORT")" == "org.uulab.veil.host-shell" ]]
LAUNCH_CONTRACT="$(plutil -extract meetsLauncherContract raw -o - "$LAUNCH_REPORT")"
[[ "$LAUNCH_CONTRACT" == "true" || "$LAUNCH_CONTRACT" == "1" ]] || {
  echo "Reinstalled Veil did not satisfy the first-window launch contract." >&2
  exit 1
}

kill "$APP_PID" >/dev/null 2>&1 || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "Veil install, replace, uninstall, support-data preservation, reinstall, and first-window launch checks passed."
