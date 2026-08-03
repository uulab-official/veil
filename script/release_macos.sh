#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---notarize}"
APP_EXECUTABLE="veil-host-shell"
BUNDLE_NAME="Veil"
BUNDLE_ID="org.uulab.veil.host-shell"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/mac-host"
RELEASE_ENTITLEMENTS="$PACKAGE_DIR/VeilHostShell.release.entitlements"
OUTPUT_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$OUTPUT_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE"
APP_ICON="$APP_RESOURCES/VeilAppIcon.icns"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ARCHIVE_PATH="$OUTPUT_DIR/$BUNDLE_NAME.zip"
NOTARY_RESULT="$OUTPUT_DIR/notary-result.json"
NOTARY_LOG="$OUTPUT_DIR/notary-log.json"
RELEASE_REPORT="$OUTPUT_DIR/release-report.plist"
SIGNING_IDENTITY="${VEIL_DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${VEIL_NOTARY_KEYCHAIN_PROFILE:-}"
RELEASE_VERSION="${VEIL_RELEASE_VERSION:-0.1.0}"
RELEASE_BUILD="${VEIL_RELEASE_BUILD:-$(date -u +%Y%m%d%H%M%S)}"

usage() {
  cat <<'USAGE'
usage: ./script/release_macos.sh [--preflight|--package|--notarize]

Required environment:
  VEIL_DEVELOPER_ID_APPLICATION   Exact "Developer ID Application: ..." identity.
  VEIL_NOTARY_KEYCHAIN_PROFILE   notarytool keychain profile (required for --preflight/--notarize).

Optional environment:
  VEIL_RELEASE_VERSION           CFBundleShortVersionString (default: 0.1.0).
  VEIL_RELEASE_BUILD             Numeric CFBundleVersion (default: UTC timestamp).
  VEIL_ALLOW_DIRTY_RELEASE=1     Explicitly allow a release from a dirty worktree.

Store notarization credentials separately before release:
  xcrun notarytool store-credentials "veil-notary" --apple-id ... --team-id ... --password ...
USAGE
}

fail() {
  echo "release blocked: $*" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command '$1' is unavailable."
}

validate_release_inputs() {
  [[ -n "$SIGNING_IDENTITY" ]] || fail "set VEIL_DEVELOPER_ID_APPLICATION to the exact Developer ID Application identity."
  [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || fail "VEIL_DEVELOPER_ID_APPLICATION must use a Developer ID Application certificate, not ad-hoc or development signing."

  if [[ "$MODE" != "--package" && "$MODE" != "package" ]]; then
    require_notary_profile
  fi

  [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || fail "VEIL_RELEASE_VERSION must contain two or three numeric components such as 0.1.0."
  [[ "$RELEASE_BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || fail "VEIL_RELEASE_BUILD must contain one to three numeric components."
}

require_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -F -- "\"$SIGNING_IDENTITY\"" >/dev/null \
    || fail "Developer ID identity '$SIGNING_IDENTITY' is not available with its private key in this keychain."
}

require_notary_profile() {
  [[ -n "$NOTARY_PROFILE" ]] || fail "set VEIL_NOTARY_KEYCHAIN_PROFILE to a notarytool keychain profile."
}

verify_notary_profile() {
  xcrun notarytool history \
    --keychain-profile "$NOTARY_PROFILE" \
    --output-format json >/dev/null \
    || fail "the notarytool profile '$NOTARY_PROFILE' could not authenticate with Apple's notary service."
}

verify_release_entitlements() {
  plutil -lint "$RELEASE_ENTITLEMENTS" >/dev/null

  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$RELEASE_ENTITLEMENTS" 2>/dev/null \
      | grep -q '^true$'; then
    fail "release entitlements must not enable com.apple.security.get-task-allow."
  fi
}

verify_clean_worktree() {
  if [[ "${VEIL_ALLOW_DIRTY_RELEASE:-0}" != "1" ]] \
      && [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)" ]]; then
    fail "the worktree is dirty; commit the release inputs or set VEIL_ALLOW_DIRTY_RELEASE=1 for an intentional local rehearsal."
  fi
}

preflight() {
  validate_release_inputs
  require_command swift
  require_command security
  require_command codesign
  require_command ditto
  require_command plutil
  require_command xcrun
  require_command spctl
  require_command shasum
  xcrun --find notarytool >/dev/null 2>&1 || fail "notarytool is unavailable; select a current Xcode toolchain."
  xcrun --find stapler >/dev/null 2>&1 || fail "stapler is unavailable; select a current Xcode toolchain."
  verify_release_entitlements
  require_signing_identity
  if [[ "$MODE" != "--package" && "$MODE" != "package" ]]; then
    verify_notary_profile
  fi
  verify_clean_worktree
  echo "release preflight passed for $SIGNING_IDENTITY"
}

stage_release_app() {
  swift build --configuration release --package-path "$PACKAGE_DIR" --product "$APP_EXECUTABLE"
  local build_binary
  build_binary="$(swift build --configuration release --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_EXECUTABLE"

  rm -rf "$APP_BUNDLE"
  rm -f "$ARCHIVE_PATH" "$NOTARY_RESULT" "$NOTARY_LOG" "$RELEASE_REPORT"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
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
  <string>$RELEASE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$RELEASE_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © UULab. All rights reserved.</string>
</dict>
</plist>
PLIST

  xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
}

sign_release_app() {
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" \
    --entitlements "$RELEASE_ENTITLEMENTS" "$APP_BINARY"
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" \
    --entitlements "$RELEASE_ENTITLEMENTS" "$APP_BUNDLE"

  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  codesign --display --verbose=4 "$APP_BUNDLE" 2>&1 \
    | grep -F "Authority=$SIGNING_IDENTITY" >/dev/null \
    || fail "the staged app is not signed by the requested Developer ID identity."

  local signed_entitlements
  signed_entitlements="$(codesign --display --entitlements :- "$APP_BUNDLE" 2>/dev/null || true)"
  if grep -q '<key>com.apple.security.get-task-allow</key>' <<<"$signed_entitlements"; then
    fail "the signed release unexpectedly contains com.apple.security.get-task-allow."
  fi
}

archive_release_app() {
  rm -f "$ARCHIVE_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
}

notarize_release() {
  xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json \
    | tee "$NOTARY_RESULT"

  local notary_status
  notary_status="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
  if [[ "$notary_status" != "Accepted" ]]; then
    local rejected_submission_id
    rejected_submission_id="$(plutil -extract id raw -o - "$NOTARY_RESULT")"
    xcrun notarytool log "$rejected_submission_id" \
      --keychain-profile "$NOTARY_PROFILE" \
      "$NOTARY_LOG" >/dev/null 2>&1 || true
    fail "Apple notarization status is '$notary_status'; inspect $NOTARY_RESULT and $NOTARY_LOG."
  fi

  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

  archive_release_app
}

write_release_report() {
  local commit_hash archive_sha notarized
  commit_hash="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  archive_sha="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
  notarized=false
  if [[ -s "$NOTARY_RESULT" ]]; then
    notarized=true
  fi

  plutil -create xml1 "$RELEASE_REPORT"
  plutil -insert bundleIdentifier -string "$BUNDLE_ID" "$RELEASE_REPORT"
  plutil -insert version -string "$RELEASE_VERSION" "$RELEASE_REPORT"
  plutil -insert build -string "$RELEASE_BUILD" "$RELEASE_REPORT"
  plutil -insert commit -string "$commit_hash" "$RELEASE_REPORT"
  plutil -insert signingIdentity -string "$SIGNING_IDENTITY" "$RELEASE_REPORT"
  plutil -insert hardenedRuntime -bool true "$RELEASE_REPORT"
  plutil -insert notarized -bool "$notarized" "$RELEASE_REPORT"
  plutil -insert archiveSHA256 -string "$archive_sha" "$RELEASE_REPORT"

  if [[ -s "$NOTARY_RESULT" ]]; then
    local submission_id
    submission_id="$(plutil -extract id raw -o - "$NOTARY_RESULT")"
    plutil -insert notarySubmissionId -string "$submission_id" "$RELEASE_REPORT"
  fi
}

case "$MODE" in
  --help|-h|help)
    usage
    ;;
  --preflight|preflight)
    preflight
    ;;
  --package|package)
    preflight
    stage_release_app
    sign_release_app
    archive_release_app
    write_release_report
    echo "Developer ID-signed rehearsal archive created at $ARCHIVE_PATH"
    echo "Do not distribute it until --notarize completes and Gatekeeper accepts the stapled app."
    ;;
  --notarize|notarize)
    preflight
    stage_release_app
    sign_release_app
    archive_release_app
    notarize_release
    write_release_report
    echo "Notarized release archive created at $ARCHIVE_PATH"
    echo "Release evidence written to $RELEASE_REPORT"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
