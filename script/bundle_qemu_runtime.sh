#!/usr/bin/env bash
# Copies QEMU, swtpm, their non-system libraries, and the Arm UEFI firmware into a Veil app bundle
# so Windows runs without Homebrew or another virtualization app on the user's Mac.
#
#   script/bundle_qemu_runtime.sh <App.app/Contents/Resources/Runtime> [signing-identity]
#
# Layout (QEMU resolves its data directory as <bin>/../share/qemu):
#   bin/qemu-system-aarch64, bin/swtpm
#   lib/*.dylib                     rewritten to @loader_path, never the build Mac's Homebrew prefix
#   share/qemu/                     keymaps, option ROMs, and UEFI firmware
#   licenses/                       upstream license texts and the source pointers in NOTICE.md
#
# The binaries come from this Mac's Homebrew `qemu` and `swtpm`. The Secure Boot firmware comes
# from Debian's `qemu-efi-aarch64` package and is pinned by SHA-256 below.
set -euo pipefail

RUNTIME_DIR="${1:?usage: bundle_qemu_runtime.sh <Runtime directory> [signing identity]}"
SIGNING_IDENTITY="${2:--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EDK2_DEB_VERSION="2025.02-8+deb13u1"
EDK2_DEB_URL="https://deb.debian.org/debian/pool/main/e/edk2/qemu-efi-aarch64_${EDK2_DEB_VERSION}_all.deb"
EDK2_DEB_SHA256="a00b2411a79c8aeafd95a7c868ac3cd1aab592f1af9fff965f02d81a625276ed"
FIRMWARE_CACHE="${VEIL_FIRMWARE_CACHE:-$HOME/Library/Caches/Veil/firmware}"

BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
QEMU_BIN="${VEIL_BUNDLE_QEMU:-${BREW_PREFIX:+$BREW_PREFIX/bin/qemu-system-aarch64}}"
SWTPM_BIN="${VEIL_BUNDLE_SWTPM:-${BREW_PREFIX:+$BREW_PREFIX/bin/swtpm}}"

if [[ -z "$QEMU_BIN" || ! -x "$QEMU_BIN" || -z "$SWTPM_BIN" || ! -x "$SWTPM_BIN" ]]; then
  echo "bundle_qemu_runtime: qemu-system-aarch64 and swtpm are required on the build Mac (brew install qemu swtpm)." >&2
  exit 1
fi

QEMU_BIN="$(readlink -f "$QEMU_BIN")"
SWTPM_BIN="$(readlink -f "$SWTPM_BIN")"
QEMU_SHARE="$(readlink -f "$(dirname "$QEMU_BIN")/../share/qemu")"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/bin" "$RUNTIME_DIR/lib" "$RUNTIME_DIR/share/qemu" "$RUNTIME_DIR/licenses"

# Non-system dependencies of one Mach-O file as "<name the load command uses> <resolved path>", with
# @rpath and @loader_path resolved against the file. The bundled copy keeps the referenced name
# (for example libjpeg.8.dylib), not the versioned file a Homebrew symlink points at.
dependencies() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    local resolved=""
    case "$dep" in
      /System/*|/usr/lib/*) continue ;;
      @loader_path/*) resolved="$(readlink -f "$dir/${dep#@loader_path/}")" ;;
      @rpath/*)
        local name="${dep#@rpath/}"
        while read -r rpath; do
          rpath="${rpath/@loader_path/$dir}"
          if [[ -e "$rpath/$name" ]]; then resolved="$(readlink -f "$rpath/$name")"; break; fi
        done < <(otool -l "$file" | awk '/LC_RPATH/{getline; getline; print $2}')
        ;;
      *) resolved="$(readlink -f "$dep")" ;;
    esac
    [[ -n "$resolved" ]] && echo "$(basename "$dep") $resolved"
  done
}

# Copy every library reachable from the binaries into lib/.
declare -a queue=("$QEMU_BIN" "$SWTPM_BIN")
declare -a copied=()
while ((${#queue[@]})); do
  current="${queue[0]}"
  queue=("${queue[@]:1}")
  while read -r name dep; do
    [[ -z "$dep" ]] && continue
    if [[ ! -e "$RUNTIME_DIR/lib/$name" ]]; then
      cp "$dep" "$RUNTIME_DIR/lib/$name"
      chmod u+w "$RUNTIME_DIR/lib/$name"
      copied+=("$name")
      queue+=("$dep")
    fi
  done < <(dependencies "$current")
done

cp "$QEMU_BIN" "$RUNTIME_DIR/bin/qemu-system-aarch64"
cp "$SWTPM_BIN" "$RUNTIME_DIR/bin/swtpm"
chmod u+w "$RUNTIME_DIR/bin/"*

# Point every load command at the bundled copy. Binaries live in bin/, libraries beside each other.
relink() {
  local file="$1"
  local prefix="$2"
  install_name_tool -delete_rpath "$(otool -l "$file" | awk '/LC_RPATH/{getline; getline; print $2; exit}')" "$file" 2>/dev/null || true
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      /System/*|/usr/lib/*) continue ;;
    esac
    local name
    name="$(basename "$dep")"
    if [[ -e "$RUNTIME_DIR/lib/$name" ]]; then
      install_name_tool -change "$dep" "$prefix/$name" "$file" 2>/dev/null
    fi
  done
}

for name in "${copied[@]}"; do
  install_name_tool -id "@loader_path/$name" "$RUNTIME_DIR/lib/$name" 2>/dev/null
  relink "$RUNTIME_DIR/lib/$name" "@loader_path"
done
relink "$RUNTIME_DIR/bin/qemu-system-aarch64" "@loader_path/../lib"
relink "$RUNTIME_DIR/bin/swtpm" "@loader_path/../lib"

# Nothing may still point at the build Mac's package prefix.
for file in "$RUNTIME_DIR"/bin/* "$RUNTIME_DIR"/lib/*; do
  if otool -L "$file" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/|/usr/lib/|@loader_path/)' >/dev/null; then
    echo "bundle_qemu_runtime: $file still links outside the bundle:" >&2
    otool -L "$file" >&2
    exit 1
  fi
done

# QEMU data Veil's Arm plan uses. Only the Secure Boot firmware below is bundled: each 64 MiB
# image would double the engine's size, and Windows 11 Setup needs Secure Boot anyway.
cp -R "$QEMU_SHARE/keymaps" "$RUNTIME_DIR/share/qemu/keymaps"
cp "$QEMU_SHARE/efi-virtio.rom" "$RUNTIME_DIR/share/qemu/efi-virtio.rom"

# Secure Boot firmware with Microsoft's keys enrolled, which Windows 11 Setup checks for.
mkdir -p "$FIRMWARE_CACHE"
deb="$FIRMWARE_CACHE/qemu-efi-aarch64_${EDK2_DEB_VERSION}_all.deb"
if [[ ! -f "$deb" ]] || [[ "$(shasum -a 256 "$deb" | awk '{print $1}')" != "$EDK2_DEB_SHA256" ]]; then
  curl --fail --silent --show-error --location --proto '=https' --output "$deb.partial" "$EDK2_DEB_URL"
  mv "$deb.partial" "$deb"
fi
if [[ "$(shasum -a 256 "$deb" | awk '{print $1}')" != "$EDK2_DEB_SHA256" ]]; then
  rm -f "$deb"
  echo "bundle_qemu_runtime: $EDK2_DEB_URL did not match the pinned SHA-256." >&2
  exit 1
fi
extract="$(mktemp -d)"
trap 'rm -rf "$extract"' EXIT
tar -xf "$deb" -C "$extract"
mkdir -p "$extract/data"
tar -xf "$extract"/data.tar.* -C "$extract/data"
cp "$extract/data/usr/share/AAVMF/AAVMF_CODE.secboot.fd" "$RUNTIME_DIR/share/qemu/edk2-aarch64-secure-code.fd"
cp "$extract/data/usr/share/AAVMF/AAVMF_VARS.ms.fd" "$RUNTIME_DIR/share/qemu/edk2-arm-secure-vars.fd"
cp "$extract/data/usr/share/doc/qemu-efi-aarch64/copyright" "$RUNTIME_DIR/licenses/edk2-debian-copyright.txt"

# License texts shipped with the binaries, plus where each exact source lives.
for formula in qemu swtpm libtpms glib; do
  cellar="$(brew --prefix "$formula" 2>/dev/null || true)"
  for license in "$cellar"/COPYING* "$cellar"/LICENSE* "$cellar"/LICENCE*; do
    [[ -f "$license" ]] && cp "$license" "$RUNTIME_DIR/licenses/$formula-$(basename "$license")"
  done
done
[[ -f "$QEMU_SHARE/edk2-licenses.txt" ]] && cp "$QEMU_SHARE/edk2-licenses.txt" "$RUNTIME_DIR/licenses/edk2-licenses.txt"
{
  echo "# Veil bundled Windows engine"
  echo
  echo "Generated by script/bundle_qemu_runtime.sh. See docs/legal-support-notes.md."
  echo
  echo "- QEMU: $("$QEMU_BIN" --version | head -1). Source: https://download.qemu.org/ (GPL-2.0)."
  echo "- swtpm: $("$SWTPM_BIN" --version | head -1). Source: https://github.com/stefanberger/swtpm (BSD-3-Clause)."
  echo "- Arm UEFI firmware: Debian qemu-efi-aarch64 $EDK2_DEB_VERSION, SHA-256 $EDK2_DEB_SHA256. Source: https://sources.debian.org/src/edk2/ (BSD-2-Clause-Patent)."
  echo "- Libraries:"
  for name in "${copied[@]}"; do
    echo "  - $name"
  done
  echo
  echo "Binaries were copied from Homebrew (https://github.com/Homebrew/homebrew-core) formulae, which"
  echo "record the upstream source tarball and patches for each version."
} > "$RUNTIME_DIR/licenses/NOTICE.md"

# install_name_tool invalidates signatures. QEMU keeps its Hypervisor.framework entitlement.
sign_flags=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  sign_flags+=(--timestamp --options runtime)
fi
for name in "${copied[@]}"; do
  codesign "${sign_flags[@]}" "$RUNTIME_DIR/lib/$name" >/dev/null 2>&1
done
codesign "${sign_flags[@]}" "$RUNTIME_DIR/bin/swtpm" >/dev/null 2>&1
codesign "${sign_flags[@]}" --entitlements "$ROOT_DIR/script/qemu-runtime.entitlements" "$RUNTIME_DIR/bin/qemu-system-aarch64" >/dev/null 2>&1

"$RUNTIME_DIR/bin/qemu-system-aarch64" --version | head -1
