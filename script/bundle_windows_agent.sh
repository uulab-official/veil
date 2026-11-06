#!/usr/bin/env bash
# Puts the Windows guest tools (Veil agent) inside the app so a released Veil can install and update
# them without this repository. Usage: bundle_windows_agent.sh <Resources dir>
# The agent is published for win-arm64 with a build id derived from its sources and scripts; the
# host compares that id with agent health to offer a tools update.
set -euo pipefail

DEST_RESOURCES="${1:?usage: bundle_windows_agent.sh <Resources dir>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="$ROOT_DIR/apps/windows-agent"
DEST="$DEST_RESOURCES/WindowsAgent"

build_id="$(
  cd "$AGENT_DIR"
  find src/VeilAgent scripts -type f ! -path '*/bin/*' ! -path '*/obj/*' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 \
    | shasum -a 256 \
    | cut -c1-12
)"

if [[ "$(cat "$AGENT_DIR/app/veil-agent-version.txt" 2>/dev/null || true)" != "0.1.0+$build_id" ]]; then
  "$AGENT_DIR/scripts/publish-veil-agent-bundle.sh" --build-id "$build_id" >/dev/null
fi

rm -rf "$DEST"
mkdir -p "$DEST/src"
ditto "$AGENT_DIR/scripts" "$DEST/scripts"
ditto "$AGENT_DIR/app" "$DEST/app"
rsync -a --exclude bin --exclude obj "$AGENT_DIR/src/" "$DEST/src/"
if [[ -d "$AGENT_DIR/package" ]]; then
  ditto "$AGENT_DIR/package" "$DEST/package"
fi
echo "Bundled Windows tools 0.1.0+$build_id"
