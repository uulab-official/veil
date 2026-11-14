#!/usr/bin/env bash
# Writes the Sparkle appcast for one Veil release archive.
#
# usage: script/make_appcast.sh <Veil.zip> <version> <build> <download URL> <appcast.xml>
#
# The EdDSA private key comes on standard input (from the SPARKLE_ED_PRIVATE_KEY secret in CI), never as
# an argument. The appcast lists only this release: Sparkle offers the newest item it can install, and an
# older Veil always moves to the latest.
set -euo pipefail

ARCHIVE="$1"
VERSION="$2"
BUILD="$3"
DOWNLOAD_URL="$4"
OUTPUT="$5"
MIN_SYSTEM_VERSION="${VEIL_MIN_SYSTEM_VERSION:-15.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$ROOT_DIR/apps/mac-host/.build/artifacts/sparkle/Sparkle/bin/sign_update}"

fail() {
  echo "appcast blocked: $*" >&2
  exit 2
}

[[ -f "$ARCHIVE" ]] || fail "no archive at $ARCHIVE."
[[ -x "$SIGN_UPDATE" ]] || fail "sign_update is missing; run 'swift package resolve' in apps/mac-host."
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "the build number must be numeric, as CFBundleVersion is."
[[ "$DOWNLOAD_URL" == https://* ]] || fail "the download URL must be HTTPS."

# Prints: sparkle:edSignature="..." length="..."
ATTRIBUTES="$("$SIGN_UPDATE" --ed-key-file - "$ARCHIVE")"
[[ "$ATTRIBUTES" == *'sparkle:edSignature="'* && "$ATTRIBUTES" == *'length="'* ]] \
  || fail "sign_update did not return a signature."

PUBLISHED="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat >"$OUTPUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Veil</title>
    <item>
      <title>Veil $VERSION</title>
      <pubDate>$PUBLISHED</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/uulab-official/veil/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$DOWNLOAD_URL" type="application/octet-stream" $ATTRIBUTES/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUTPUT"
