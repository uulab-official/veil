#!/usr/bin/env bash
# Copies QEMU, swtpm, their non-system libraries, and the Arm UEFI firmware into a Veil app bundle
# so Windows runs without Homebrew or another virtualization app on the user's Mac.
#
#   script/bundle_qemu_runtime.sh <App.app/Contents/Resources/Runtime> [signing-identity]
#
# Layout (QEMU resolves its data directory as <bin>/../share/qemu):
#   bin/qemu-system-aarch64, bin/swtpm, bin/qemu-img (qcow2 disks, resize, snapshots)
#   bin/qemu-system-x86_64          TCG-only x86_64 emulator for non-Windows guests; about 30 MB with
#                                   its firmware (docs/architecture.md). VEIL_BUNDLE_X86=0 leaves it out.
#   lib/*.dylib                     rewritten to @loader_path, never the build Mac's Homebrew prefix
#   share/qemu/                     keymaps, the virtio option ROM, QEMU's Arm UEFI firmware, and
#                                   Veil's Secure Boot build (script/build_secure_firmware.sh)
#   licenses/                       upstream license texts and the source pointers in NOTICE.md
#
# The binaries and firmware come from this Mac's Homebrew `qemu` (qemu-system-aarch64, qemu-img)
# and `swtpm`.
set -euo pipefail

RUNTIME_DIR="${1:?usage: bundle_qemu_runtime.sh <Runtime directory> [signing identity]}"
SIGNING_IDENTITY="${2:--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"


BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
QEMU_BIN="${VEIL_BUNDLE_QEMU:-${BREW_PREFIX:+$BREW_PREFIX/bin/qemu-system-aarch64}}"
SWTPM_BIN="${VEIL_BUNDLE_SWTPM:-${BREW_PREFIX:+$BREW_PREFIX/bin/swtpm}}"
# qemu-img comes from the same qemu formula, so it is looked up beside qemu-system-aarch64.
QEMU_IMG_BIN="${VEIL_BUNDLE_QEMU_IMG:-${QEMU_BIN:+$(dirname "$QEMU_BIN")/qemu-img}}"
QEMU_X86_BIN=""
if [[ "${VEIL_BUNDLE_X86:-1}" != "0" ]]; then
  QEMU_X86_BIN="${VEIL_BUNDLE_QEMU_X86:-${BREW_PREFIX:+$BREW_PREFIX/bin/qemu-system-x86_64}}"
  if [[ -z "$QEMU_X86_BIN" || ! -x "$QEMU_X86_BIN" ]]; then
    echo "bundle_qemu_runtime: qemu-system-x86_64 is missing; set VEIL_BUNDLE_X86=0 to bundle without x86_64 emulation." >&2
    exit 1
  fi
  QEMU_X86_BIN="$(readlink -f "$QEMU_X86_BIN")"
fi

if [[ -z "$QEMU_BIN" || ! -x "$QEMU_BIN" || -z "$SWTPM_BIN" || ! -x "$SWTPM_BIN" || -z "$QEMU_IMG_BIN" || ! -x "$QEMU_IMG_BIN" ]]; then
  echo "bundle_qemu_runtime: qemu-system-aarch64, qemu-img, and swtpm are required on the build Mac (brew install qemu swtpm)." >&2
  exit 1
fi

QEMU_BIN="$(readlink -f "$QEMU_BIN")"
SWTPM_BIN="$(readlink -f "$SWTPM_BIN")"
QEMU_IMG_BIN="$(readlink -f "$QEMU_IMG_BIN")"
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
declare -a queue=("$QEMU_BIN" "$SWTPM_BIN" "$QEMU_IMG_BIN" ${QEMU_X86_BIN:+"$QEMU_X86_BIN"})
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
cp "$QEMU_IMG_BIN" "$RUNTIME_DIR/bin/qemu-img"
[[ -n "$QEMU_X86_BIN" ]] && cp "$QEMU_X86_BIN" "$RUNTIME_DIR/bin/qemu-system-x86_64"
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
relink "$RUNTIME_DIR/bin/qemu-img" "@loader_path/../lib"
[[ -n "$QEMU_X86_BIN" ]] && relink "$RUNTIME_DIR/bin/qemu-system-x86_64" "@loader_path/../lib"

# Nothing may still point at the build Mac's package prefix.
for file in "$RUNTIME_DIR"/bin/* "$RUNTIME_DIR"/lib/*; do
  if otool -L "$file" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/|/usr/lib/|@loader_path/)' >/dev/null; then
    echo "bundle_qemu_runtime: $file still links outside the bundle:" >&2
    otool -L "$file" >&2
    exit 1
  fi
done

# QEMU data Veil's Arm plan uses, with QEMU's own Arm UEFI firmware.
cp -R "$QEMU_SHARE/keymaps" "$RUNTIME_DIR/share/qemu/keymaps"
for file in efi-virtio.rom edk2-aarch64-code.fd edk2-arm-vars.fd; do
  cp "$QEMU_SHARE/$file" "$RUNTIME_DIR/share/qemu/$file"
done
# x86_64 guests: OVMF with an empty variable store, the option ROM the standard VGA loads, and the
# vAPIC ROM every x86 machine probes for at startup.
if [[ -n "$QEMU_X86_BIN" ]]; then
  for file in edk2-x86_64-code.fd edk2-i386-vars.fd vgabios-stdvga.bin kvmvapic.bin; do
    cp "$QEMU_SHARE/$file" "$RUNTIME_DIR/share/qemu/$file"
  done
fi

# Veil's own Secure Boot firmware, built from EDK2 by script/build_secure_firmware.sh (cached).
# Debian's qemu-efi-aarch64 builds stop at "Start boot option" with the Windows 11 Arm ISO, so no
# distribution firmware is used. Without it, Veil falls back to ~/Library/Application
# Support/Veil/Firmware or an installed UTM. VEIL_SKIP_SECURE_FIRMWARE=1 skips the build.
SECURE_FIRMWARE_DIR="${VEIL_SECURE_FIRMWARE_DIR:-$ROOT_DIR/dist/.secure-firmware}"
secure_firmware_bundled=0
if [[ "${VEIL_SKIP_SECURE_FIRMWARE:-0}" != "1" ]] && "$ROOT_DIR/script/build_secure_firmware.sh" "$SECURE_FIRMWARE_DIR"; then
  cp "$SECURE_FIRMWARE_DIR/edk2-aarch64-secure-code.fd" "$SECURE_FIRMWARE_DIR/edk2-arm-secure-vars.fd" "$RUNTIME_DIR/share/qemu/"
  cp "$SECURE_FIRMWARE_DIR/PROVENANCE.md" "$RUNTIME_DIR/licenses/edk2-secure-PROVENANCE.md"
  cp "$SECURE_FIRMWARE_DIR/edk2-License.txt" "$RUNTIME_DIR/licenses/edk2-License.txt"
  secure_firmware_bundled=1
else
  echo "bundle_qemu_runtime: bundling without Secure Boot firmware." >&2
fi

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
  echo "- qemu-img: $("$QEMU_IMG_BIN" --version | head -1). Same QEMU source (GPL-2.0)."
  echo "- swtpm: $("$SWTPM_BIN" --version | head -1). Source: https://github.com/stefanberger/swtpm (BSD-3-Clause)."
  echo "- Arm UEFI firmware: QEMU's edk2-aarch64-code.fd. Source: https://github.com/tianocore/edk2 (BSD-2-Clause-Patent); see edk2-licenses.txt."
  if [[ -n "$QEMU_X86_BIN" ]]; then
    echo "- x86_64 UEFI firmware: QEMU's edk2-x86_64-code.fd (OVMF) and edk2-i386-vars.fd; VGA BIOS: QEMU's vgabios-stdvga.bin (SeaBIOS/SeaVGABIOS, LGPL-3.0)."
  fi
  if ((secure_firmware_bundled)); then
    echo "- Secure Boot Arm UEFI firmware: built from EDK2 by Veil; see edk2-secure-PROVENANCE.md and edk2-License.txt."
  fi
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
codesign "${sign_flags[@]}" "$RUNTIME_DIR/bin/qemu-img" >/dev/null 2>&1
codesign "${sign_flags[@]}" --entitlements "$ROOT_DIR/script/qemu-runtime.entitlements" "$RUNTIME_DIR/bin/qemu-system-aarch64" >/dev/null 2>&1
# TCG writes the code it translates into MAP_JIT memory, which the hardened runtime refuses without
# allow-jit; it never touches Hypervisor.framework.
[[ -n "$QEMU_X86_BIN" ]] && codesign "${sign_flags[@]}" --entitlements "$ROOT_DIR/script/qemu-tcg-runtime.entitlements" "$RUNTIME_DIR/bin/qemu-system-x86_64" >/dev/null 2>&1

"$RUNTIME_DIR/bin/qemu-system-aarch64" --version | head -1
"$RUNTIME_DIR/bin/qemu-img" --version | head -1
