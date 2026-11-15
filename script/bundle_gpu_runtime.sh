#!/usr/bin/env bash
# Copies the GPU acceleration runtime (Triton) into a Veil app bundle, beside the software runtime.
#
#   script/bundle_gpu_runtime.sh <App.app/Contents/Resources/RuntimeGPU> [signing-identity]
#
# Input: a Triton build prefix (VEIL_TRITON_PREFIX, default ~/VeilTriton/prefix) made as in
# docs/checklists/2026-11-10-triton-gpu-acceleration-evaluation.md, section 2, with the patches in
# script/qemu-patches/triton/ applied to UTM's QEMU. It holds:
#   bin/qemu-system-aarch64                  UTM's utm-edition fork (QEMU 10.0)
#   libexec/virgl_render_server              virglrenderer's render server (Neptune renderer)
#   lib/libvirglrenderer.1.dylib, lib/libepoxy.0.dylib, lib/libdxmt-native.dylib
#   ANGLE.xcarchive/Products/usr/local/lib/libEGL.dylib, libGLESv2.dylib
#   share/qemu/                              QEMU's data files
#
# Layout written (QEMU resolves its data directory as <bin>/../share/qemu):
#   bin/qemu-system-aarch64, libexec/virgl_render_server
#   lib/*.dylib        every non-system library, rewritten to @loader_path; QEMU and the render server
#                      also get an LC_RPATH to lib/, because libepoxy opens libEGL.dylib and Neptune
#                      opens DXMT by leaf name, which dyld then looks up along the caller's rpaths
#   share/qemu/        keymaps and the virtio option ROM (firmware comes from the software runtime)
#   licenses/          upstream licenses, the Veil patches, and PROVENANCE.md with the exact sources
#
# Veil starts QEMU with RENDER_SERVER_EXEC_PATH and NPT_D3D11_LIBRARY_PATH pointing into this folder
# (QEMUGPURuntime.processEnvironment). DXMT is the only D3D11 backend: Apple's D3DMetal may not be
# redistributed.
set -euo pipefail

RUNTIME_DIR="${1:?usage: bundle_gpu_runtime.sh <RuntimeGPU directory> [signing identity]}"
SIGNING_IDENTITY="${2:--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${VEIL_TRITON_PREFIX:-$HOME/VeilTriton/prefix}"
SOURCES="${VEIL_TRITON_SOURCES:-$(dirname "$PREFIX")/src}"
ANGLE_LIB="$PREFIX/ANGLE.xcarchive/Products/usr/local/lib"

fail() {
  echo "bundle_gpu_runtime: $*" >&2
  exit 1
}

for required in bin/qemu-system-aarch64 libexec/virgl_render_server lib/libdxmt-native.dylib share/qemu/efi-virtio.rom share/qemu/vgabios-ramfb.bin; do
  [[ -e "$PREFIX/$required" ]] || fail "$PREFIX/$required is missing; build the Triton prefix first."
done
for required in libEGL.dylib libGLESv2.dylib; do
  [[ -e "$ANGLE_LIB/$required" ]] || fail "$ANGLE_LIB/$required is missing; build ANGLE first."
done

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/bin" "$RUNTIME_DIR/libexec" "$RUNTIME_DIR/lib" "$RUNTIME_DIR/share/qemu" "$RUNTIME_DIR/licenses"

# Non-system dependencies of one Mach-O file as "<leaf name> <resolved path>".
dependencies() {
  local file="$1" dir
  dir="$(dirname "$file")"
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    local resolved=""
    case "$dep" in
      /System/*|/usr/lib/*) continue ;;
      @loader_path/*) resolved="$(readlink -f "$dir/${dep#@loader_path/}" 2>/dev/null || true)" ;;
      @rpath/*)
        local name="${dep#@rpath/}"
        for candidate in "$dir/$name" "$PREFIX/lib/$name" "$ANGLE_LIB/$name"; do
          [[ -e "$candidate" ]] && { resolved="$(readlink -f "$candidate")"; break; }
        done
        ;;
      *) resolved="$(readlink -f "$dep" 2>/dev/null || true)" ;;
    esac
    # A library's own install name is listed first; skip it.
    [[ -n "$resolved" && "$resolved" != "$(readlink -f "$file")" ]] && echo "$(basename "$dep") $resolved"
  done
}

cp "$PREFIX/bin/qemu-system-aarch64" "$RUNTIME_DIR/bin/"
cp "$PREFIX/libexec/virgl_render_server" "$RUNTIME_DIR/libexec/"
# Loaded with dlopen, so no load command leads to them.
cp "$PREFIX/lib/libdxmt-native.dylib" "$ANGLE_LIB/libEGL.dylib" "$ANGLE_LIB/libGLESv2.dylib" "$RUNTIME_DIR/lib/"
chmod u+w "$RUNTIME_DIR"/bin/* "$RUNTIME_DIR"/libexec/* "$RUNTIME_DIR"/lib/*

declare -a queue=("$RUNTIME_DIR/bin/qemu-system-aarch64" "$RUNTIME_DIR/libexec/virgl_render_server" \
  "$RUNTIME_DIR/lib/libdxmt-native.dylib" "$RUNTIME_DIR/lib/libEGL.dylib" "$RUNTIME_DIR/lib/libGLESv2.dylib")
while ((${#queue[@]})); do
  current="${queue[0]}"
  queue=("${queue[@]:1}")
  while read -r name dep; do
    [[ -z "$dep" ]] && continue
    if [[ ! -e "$RUNTIME_DIR/lib/$name" ]]; then
      cp "$dep" "$RUNTIME_DIR/lib/$name"
      chmod u+w "$RUNTIME_DIR/lib/$name"
      queue+=("$RUNTIME_DIR/lib/$name")
    fi
  done < <(dependencies "$current")
done

relink() {
  local file="$1" prefix="$2"
  while read -r rpath; do
    install_name_tool -delete_rpath "$rpath" "$file" 2>/dev/null || true
  done < <(otool -l "$file" | awk '/LC_RPATH/{getline; getline; print $2}')
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      /System/*|/usr/lib/*) continue ;;
    esac
    local name
    name="$(basename "$dep")"
    if [[ -e "$RUNTIME_DIR/lib/$name" && "$dep" != "$prefix/$name" ]]; then
      install_name_tool -change "$dep" "$prefix/$name" "$file" 2>/dev/null
    fi
  done
}

for library in "$RUNTIME_DIR"/lib/*.dylib; do
  name="$(basename "$library")"
  install_name_tool -id "@loader_path/$name" "$library" 2>/dev/null
  relink "$library" "@loader_path"
done
relink "$RUNTIME_DIR/bin/qemu-system-aarch64" "@loader_path/../lib"
relink "$RUNTIME_DIR/libexec/virgl_render_server" "@loader_path/../lib"
install_name_tool -add_rpath "@loader_path/../lib" "$RUNTIME_DIR/bin/qemu-system-aarch64"
install_name_tool -add_rpath "@loader_path/../lib" "$RUNTIME_DIR/libexec/virgl_render_server"
install_name_tool -add_rpath "@loader_path" "$RUNTIME_DIR/lib/libepoxy.0.dylib"

for file in "$RUNTIME_DIR"/bin/* "$RUNTIME_DIR"/libexec/* "$RUNTIME_DIR"/lib/*; do
  if otool -L "$file" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/|/usr/lib/|@loader_path/)' >/dev/null; then
    echo "bundle_gpu_runtime: $file still links outside the bundle:" >&2
    otool -L "$file" >&2
    exit 1
  fi
done

cp -R "$PREFIX/share/qemu/keymaps" "$RUNTIME_DIR/share/qemu/keymaps"
cp "$PREFIX/share/qemu/efi-virtio.rom" "$PREFIX/share/qemu/vgabios-ramfb.bin" "$RUNTIME_DIR/share/qemu/"

# Triton's Windows driver, which Veil puts on the GPU driver disc (GPUDriverMedia). Only the release Veil
# pins: osy/kvm-guest-drivers-windows v0.5, attestation-signed by Microsoft. The agent checks the catalog and
# INF again inside Windows (GpuDriverInstall.PinnedHashes).
DRIVER_ZIP="${VEIL_TRITON_DRIVER_ZIP:-$(dirname "$PREFIX")/drivers/v0.5/viogpu3d-arm64x-signed.zip}"
DRIVER_ZIP_SHA256="155695ab7820f71e75c369aeae7b8c060691ba43646ac37edef72aa2428506d5"
[[ -f "$DRIVER_ZIP" ]] || fail "$DRIVER_ZIP is missing; download viogpu3d-arm64x-signed.zip from https://github.com/osy/kvm-guest-drivers-windows/releases/tag/v0.5."
[[ "$(shasum -a 256 "$DRIVER_ZIP" | cut -d' ' -f1)" == "$DRIVER_ZIP_SHA256" ]] \
  || fail "$DRIVER_ZIP does not match the pinned SHA-256 of the v0.5 release."
driver_staging="$(mktemp -d)"
unzip -q "$DRIVER_ZIP" -d "$driver_staging"
mkdir -p "$RUNTIME_DIR/guest-driver"
cp -R "$driver_staging/drivers/viogpu3d" "$RUNTIME_DIR/guest-driver/viogpu3d"
rm -rf "$driver_staging"
[[ "$(shasum -a 256 "$RUNTIME_DIR/guest-driver/viogpu3d/viogpu3d.cat" | cut -d' ' -f1)" == "a7a8f2b5ae8c323b5a8108a9793f3f6b4ecf2103f317c02038351ff3300380b9" ]] \
  || fail "the driver catalog does not match the one the Windows agent pins."

# Licenses and the exact sources.
cp -R "$ROOT_DIR/script/qemu-patches/triton" "$RUNTIME_DIR/licenses/qemu-patches"
copy_license() {
  local source="$1" target="$2"
  [[ -f "$source" ]] && cp "$source" "$RUNTIME_DIR/licenses/$target"
}
copy_license "$SOURCES/qemu/COPYING" qemu-COPYING
copy_license "$SOURCES/qemu/LICENSE" qemu-LICENSE
copy_license "$SOURCES/virglrenderer/COPYING" virglrenderer-COPYING
copy_license "$SOURCES/libepoxy/COPYING" libepoxy-COPYING
copy_license "$SOURCES/dxmt/LICENSE" dxmt-LICENSE
copy_license "$SOURCES/WebKit/Source/ThirdParty/ANGLE/LICENSE" angle-LICENSE
commit() {
  git -C "$SOURCES/$1" rev-parse HEAD 2>/dev/null || echo "unknown"
}
{
  echo "# Veil GPU runtime (Triton)"
  echo
  echo "Generated by script/bundle_gpu_runtime.sh. Built as in docs/checklists/2026-11-10-triton-gpu-acceleration-evaluation.md."
  echo
  echo "- QEMU: $("$PREFIX/bin/qemu-system-aarch64" --version | head -1), https://github.com/utmapp/qemu branch utm-edition at $(commit qemu) (GPL-2.0), with Veil's patches in qemu-patches/."
  echo "- virglrenderer: https://github.com/utmapp/virglrenderer branch macos-next at $(commit virglrenderer) (MIT)."
  echo "- libepoxy: https://github.com/utmapp/libepoxy branch macos-venus at $(commit libepoxy) (MIT)."
  echo "- DXMT: https://github.com/utmapp/dxmt at $(commit dxmt) (LGPL-2.1-or-later; a separate, replaceable libdxmt-native.dylib). LLVM 15.0.7 is linked into it (Apache-2.0 with LLVM exception)."
  echo "- ANGLE: https://github.com/utmapp/WebKit at $(commit WebKit) (BSD-3-Clause)."
  echo "- Windows driver (guest-driver/viogpu3d): https://github.com/osy/kvm-guest-drivers-windows release v0.5, viogpu3d-arm64x-signed.zip (SHA-256 $DRIVER_ZIP_SHA256), BSD-3-Clause; user-mode parts from https://github.com/osy/virtio-win-mesa (MIT)."
  echo "- Libraries:"
  for library in "$RUNTIME_DIR"/lib/*.dylib; do
    echo "  - $(basename "$library")"
  done
} > "$RUNTIME_DIR/licenses/PROVENANCE.md"

# install_name_tool invalidates signatures. QEMU keeps its Hypervisor.framework entitlement.
sign_flags=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  sign_flags+=(--timestamp --options runtime)
fi
for library in "$RUNTIME_DIR"/lib/*.dylib; do
  codesign "${sign_flags[@]}" "$library" >/dev/null 2>&1
done
codesign "${sign_flags[@]}" "$RUNTIME_DIR/libexec/virgl_render_server" >/dev/null 2>&1
codesign "${sign_flags[@]}" --entitlements "$ROOT_DIR/script/qemu-runtime.entitlements" "$RUNTIME_DIR/bin/qemu-system-aarch64" >/dev/null 2>&1

"$RUNTIME_DIR/bin/qemu-system-aarch64" --version | head -1
