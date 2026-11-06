#!/usr/bin/env bash
# Gathers the corresponding source for the Windows engine bundled in a release, so the GitHub
# release carries it next to the app as GPL-2.0 section 3(a) and LGPL-2.1 section 6 ask.
#
#   script/collect_engine_sources.sh <output directory>
#
# Output:
#   SOURCES.md                         every bundled Homebrew formula with its version, license,
#                                      source URL, and formula file (Homebrew's patches live there)
#   engine-sources/<tarball>           the upstream source of each copyleft-licensed formula
#   engine-sources/edk2.txt            the EDK2 commit the Secure Boot firmware is built from
#
# It reads the formulae installed on this Mac, which are the ones bundle_qemu_runtime.sh copied.
set -euo pipefail

OUT_DIR="${1:?usage: collect_engine_sources.sh <output directory>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$OUT_DIR/engine-sources"

formulae=(qemu swtpm)
while read -r dependency; do
  formulae+=("$dependency")
done < <(brew deps --installed --union qemu swtpm)

brew info --json=v2 "${formulae[@]}" >"$OUT_DIR/formulae.json"

python3 -I - "$OUT_DIR/formulae.json" "$OUT_DIR" <<'PY'
import json, sys, pathlib
info = json.load(open(sys.argv[1]))["formulae"]
out = pathlib.Path(sys.argv[2])
rows, downloads = [], []
for formula in sorted(info, key=lambda f: f["name"]):
    url = (formula.get("urls", {}).get("stable") or {}).get("url", "")
    version = formula["versions"]["stable"]
    license_text = formula.get("license") or "unknown"
    rows.append(f"| {formula['name']} | {version} | {license_text} | {url} | "
                f"https://github.com/Homebrew/homebrew-core/blob/master/Formula/{formula['name'][0]}/{formula['name']}.rb |")
    if "GPL" in license_text and url:
        downloads.append(f"{formula['name']} {url}")
(out / "SOURCES.md").write_text(
    "# Veil Windows engine sources\n\n"
    "The engine bundled in Veil.app is built from these Homebrew formulae. Copyleft sources are "
    "attached to this release as engine-sources.tar; Homebrew's patches are in each formula file.\n\n"
    "| Formula | Version | License | Source | Formula |\n|---|---|---|---|---|\n"
    + "\n".join(rows) + "\n")
(out / "downloads.txt").write_text("\n".join(downloads) + "\n")
PY

while read -r name url; do
  [[ -z "$url" ]] && continue
  file="$(basename "${url%%\?*}")"
  [[ "$file" == "$name"* ]] || file="$name-$file"
  curl -fsSL --retry 3 -o "$OUT_DIR/engine-sources/$file" "$url"
done <"$OUT_DIR/downloads.txt"

commit="$(sed -n 's/^EDK2_COMMIT="\(.*\)"$/\1/p' "$ROOT_DIR/script/build_secure_firmware.sh")"
echo "Secure Boot firmware: https://github.com/tianocore/edk2/tree/$commit (built by script/build_secure_firmware.sh)" \
  >"$OUT_DIR/engine-sources/edk2.txt"
echo >>"$OUT_DIR/SOURCES.md"
echo "## Secure Boot firmware" >>"$OUT_DIR/SOURCES.md"
echo >>"$OUT_DIR/SOURCES.md"
echo "Built from https://github.com/tianocore/edk2 at \`$commit\` by \`script/build_secure_firmware.sh\` (BSD-2-Clause-Patent)." >>"$OUT_DIR/SOURCES.md"

tar -cf "$OUT_DIR/engine-sources.tar" -C "$OUT_DIR" engine-sources
rm -rf "$OUT_DIR/engine-sources" "$OUT_DIR/downloads.txt" "$OUT_DIR/formulae.json"
