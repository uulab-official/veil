#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/Veil.app"
DESTINATION_APP="/Applications/Veil.app"
EXPECTED_BUNDLE_ID="org.uulab.veil.host-shell"
REPLACE_EXISTING=0
TEMP_APP=""
BACKUP_APP=""

usage() {
  cat <<'USAGE'
usage: ./script/install_macos.sh [--source <Veil.app>] [--destination <Veil.app>] [--replace]

Installs a signed Veil app bundle. Existing apps are never overwritten unless
--replace is supplied, and only an existing Veil bundle may be replaced.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "--source requires a path." >&2; exit 2; }
      SOURCE_APP="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || { echo "--destination requires a path." >&2; exit 2; }
      DESTINATION_APP="$2"
      shift 2
      ;;
    --replace)
      REPLACE_EXISTING=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

bundle_identifier() {
  plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null
}

validate_veil_bundle() {
  local app_path="$1"
  local role="$2"

  [[ -d "$app_path" ]] || { echo "$role app bundle does not exist: $app_path" >&2; return 1; }
  [[ -f "$app_path/Contents/Info.plist" ]] || { echo "$role app has no Info.plist: $app_path" >&2; return 1; }
  [[ -x "$app_path/Contents/MacOS/veil-host-shell" ]] || { echo "$role app executable is missing: $app_path" >&2; return 1; }

  local actual_bundle_id
  actual_bundle_id="$(bundle_identifier "$app_path")"
  [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || {
    echo "$role app bundle identifier is $actual_bundle_id, expected $EXPECTED_BUNDLE_ID." >&2
    return 1
  }

  codesign --verify --deep --strict "$app_path"
}

cleanup() {
  local status=$?

  if [[ -n "$TEMP_APP" && -e "$TEMP_APP" ]]; then
    rm -rf "$TEMP_APP"
  fi

  if [[ "$status" -ne 0 && -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    if [[ -e "$DESTINATION_APP" ]]; then
      rm -rf "$DESTINATION_APP"
    fi
    mv "$BACKUP_APP" "$DESTINATION_APP"
  fi

  if [[ "$status" -eq 0 && -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    rm -rf "$BACKUP_APP"
  fi

  exit "$status"
}
trap cleanup EXIT

validate_veil_bundle "$SOURCE_APP" "Source"

DESTINATION_PARENT="$(dirname "$DESTINATION_APP")"
mkdir -p "$DESTINATION_PARENT"

if [[ -e "$DESTINATION_APP" ]]; then
  [[ "$REPLACE_EXISTING" -eq 1 ]] || {
    echo "Destination already exists: $DESTINATION_APP. Re-run with --replace to update Veil." >&2
    exit 1
  }
  validate_veil_bundle "$DESTINATION_APP" "Existing destination"
fi

TEMP_APP="$DESTINATION_APP.installing.$$"
BACKUP_APP="$DESTINATION_APP.backup.$$"
[[ ! -e "$TEMP_APP" && ! -e "$BACKUP_APP" ]] || {
  echo "Temporary install paths already exist beside $DESTINATION_APP." >&2
  exit 1
}

ditto "$SOURCE_APP" "$TEMP_APP"
xattr -dr com.apple.quarantine "$TEMP_APP" 2>/dev/null || true
validate_veil_bundle "$TEMP_APP" "Copied"

if [[ -e "$DESTINATION_APP" ]]; then
  mv "$DESTINATION_APP" "$BACKUP_APP"
fi
mv "$TEMP_APP" "$DESTINATION_APP"
TEMP_APP=""

validate_veil_bundle "$DESTINATION_APP" "Installed"
echo "Installed Veil at $DESTINATION_APP"
