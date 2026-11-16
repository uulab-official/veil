#!/usr/bin/env bash
# Writes Metadata.appintents for the Veil app bundle.
#
# Shortcuts and Siri only list an app's App Intents when the bundle carries Metadata.appintents. Xcode
# produces it in an "Extract App Intents Metadata" build phase; `swift build` does not run that phase for an
# executable product, so a SwiftPM-built Veil.app would contain the intent code but show nothing in
# Shortcuts. The compiler half already happens under SwiftPM's build system: every Swift file gets a
# `.swiftconstvalues` file for the App Intents protocols. This script runs the other half, Xcode's own
# `appintentsmetadataprocessor`, over those files and the linked binary.
#
# Usage: extract_app_intents_metadata.sh <debug|release> <app-binary> <app-resources-dir>
set -euo pipefail

CONFIGURATION="$1"
APP_BINARY="$2"
APP_RESOURCES="$3"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/mac-host"
MODULE_NAME="VeilHostShell"
PRODUCT_NAME="veil-host-shell"
DEPLOYMENT_TARGET="15.0"

fail() {
  echo "error: App Intents metadata: $*" >&2
  exit 1
}

case "$CONFIGURATION" in
  debug) config_dir="Debug" ;;
  release) config_dir="Release" ;;
  *) fail "configuration must be debug or release, not '$CONFIGURATION'." ;;
esac

processor="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)" \
  || fail "appintentsmetadataprocessor was not found. Install Xcode and select it with xcode-select."

bin_path="$(swift build --configuration "$CONFIGURATION" --package-path "$PACKAGE_DIR" --show-bin-path)"
# Products/<Config> sits next to Intermediates.noindex under SwiftPM's build-system output directory.
intermediates="$(dirname "$(dirname "$bin_path")")/Intermediates.noindex"
const_values_dir="$(find "$intermediates" -type d -path "*/$config_dir/$PRODUCT_NAME-*.build" -print -quit 2>/dev/null || true)"
[[ -n "$const_values_dir" ]] \
  || fail "no build intermediates for $PRODUCT_NAME under $intermediates. Build with SwiftPM's default build system."

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

find "$PACKAGE_DIR/Sources/$MODULE_NAME" -name '*.swift' >"$work_dir/sources.txt"
find "$const_values_dir" -name '*.swiftconstvalues' >"$work_dir/const-values.txt"
intent_files="$(tr '\n' '\0' <"$work_dir/const-values.txt" | xargs -0 grep -l 'AppIntents.AppIntent' 2>/dev/null || true)"
[[ -n "$intent_files" ]] \
  || fail "the compiler did not record any App Intents in $const_values_dir."

toolchain_dir="$(cd "$(dirname "$(xcrun --find swiftc)")/../.." && pwd)"
xcode_build="$(xcodebuild -version | awk '/Build version/ {print $3}')"

"$processor" \
  --output "$work_dir/out" \
  --toolchain-dir "$toolchain_dir" \
  --module-name "$MODULE_NAME" \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$xcode_build" \
  --platform-family macOS \
  --deployment-target "$DEPLOYMENT_TARGET" \
  --target-triple "arm64-apple-macos$DEPLOYMENT_TARGET" \
  --source-file-list "$work_dir/sources.txt" \
  --swift-const-vals-list "$work_dir/const-values.txt" \
  --binary-file "$APP_BINARY" \
  --force \
  >"$work_dir/processor.log" 2>&1 \
  || { cat "$work_dir/processor.log" >&2; fail "appintentsmetadataprocessor failed."; }

metadata="$work_dir/out/Metadata.appintents"
[[ -f "$metadata/extract.actionsdata" ]] || fail "the processor wrote no Metadata.appintents."
grep -q '"StartWindowsIntent"' "$metadata/extract.actionsdata" \
  || fail "Metadata.appintents does not list StartWindowsIntent."

rm -rf "$APP_RESOURCES/Metadata.appintents"
ditto "$metadata" "$APP_RESOURCES/Metadata.appintents"
