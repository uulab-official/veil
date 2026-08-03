#!/usr/bin/env bash
set -euo pipefail

DESTINATION_APP="/Applications/Veil.app"
TRASH_DIRECTORY="$HOME/.Trash"
EXPECTED_BUNDLE_ID="org.uulab.veil.host-shell"

usage() {
  cat <<'USAGE'
usage: ./script/uninstall_macos.sh [--destination <Veil.app>] [--trash-directory <directory>]

Moves only the Veil app bundle to Trash. VM disks, Windows media, profiles,
diagnostics, shared folders, and other Application Support data are preserved.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      [[ $# -ge 2 ]] || { echo "--destination requires a path." >&2; exit 2; }
      DESTINATION_APP="$2"
      shift 2
      ;;
    --trash-directory)
      [[ $# -ge 2 ]] || { echo "--trash-directory requires a path." >&2; exit 2; }
      TRASH_DIRECTORY="$2"
      shift 2
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

if [[ ! -e "$DESTINATION_APP" ]]; then
  echo "Veil is already uninstalled from $DESTINATION_APP"
  exit 0
fi

[[ -d "$DESTINATION_APP" && -f "$DESTINATION_APP/Contents/Info.plist" ]] || {
  echo "Refusing to move a non-app destination: $DESTINATION_APP" >&2
  exit 1
}

ACTUAL_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$DESTINATION_APP/Contents/Info.plist" 2>/dev/null)"
[[ "$ACTUAL_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || {
  echo "Refusing to move bundle $ACTUAL_BUNDLE_ID; expected $EXPECTED_BUNDLE_ID." >&2
  exit 1
}

mkdir -p "$TRASH_DIRECTORY"
TRASH_APP="$TRASH_DIRECTORY/Veil.app"
COUNTER=1
while [[ -e "$TRASH_APP" ]]; do
  TRASH_APP="$TRASH_DIRECTORY/Veil $COUNTER.app"
  COUNTER=$((COUNTER + 1))
done

mv "$DESTINATION_APP" "$TRASH_APP"
echo "Moved Veil to $TRASH_APP"
echo "Veil user data was preserved. Reinstalling the app will restore the existing local setup."

