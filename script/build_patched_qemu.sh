#!/usr/bin/env bash
# Builds qemu-system-aarch64 from the QEMU release Homebrew ships, with Veil's patches applied.
#
#   script/build_patched_qemu.sh [output directory]   (default: dist/.patched-qemu)
#
# Output:
#   qemu-system-aarch64   HVF, Cocoa, VNC, slirp; signed ad hoc with the hypervisor entitlement
#   patches/              the patches applied, shipped with the binary (GPL-2.0)
#   PROVENANCE.md         the exact source, patches, and configure options
#
# Only qemu-system-aarch64 is rebuilt. qemu-img, qemu-system-x86_64, and QEMU's data files still
# come from Homebrew, so the pinned version must match Homebrew's `qemu`; otherwise this script
# fails and script/bundle_qemu_runtime.sh bundles Homebrew's unpatched binary. See
# script/qemu-patches/README.md for what each patch does.
#
# Needs Homebrew's qemu build dependencies (brew install meson ninja pkgconf glib pixman libslirp
# dtc capstone zstd libpng jpeg-turbo). The result is cached until this script or a patch changes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist/.patched-qemu}"
PATCH_DIR="$ROOT_DIR/script/qemu-patches"
QEMU_VERSION="11.1.3"
QEMU_URL="https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz"
# The checksum Homebrew's qemu formula pins for the same tarball.
QEMU_SHA256="5a8289c7940dc77d3873c81a6c29ba3afe1446fc9d36e77fa1658cdbecb84b22"

STAMP="$(cat "${BASH_SOURCE[0]}" "$PATCH_DIR"/*.patch | shasum | cut -c1-16)"
if [[ "$(cat "$OUT_DIR/.stamp" 2>/dev/null || true)" == "$STAMP" && -x "$OUT_DIR/qemu-system-aarch64" ]]; then
  exit 0
fi

fail() {
  echo "build_patched_qemu: $*" >&2
  exit 1
}

BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
[[ -n "$BREW_PREFIX" ]] || fail "Homebrew is required."
brew_version="$("$BREW_PREFIX/bin/qemu-system-aarch64" --version 2>/dev/null | head -1 | awk '{print $4}')"
[[ "$brew_version" == "$QEMU_VERSION" ]] \
  || fail "Homebrew's qemu is ${brew_version:-missing}, not $QEMU_VERSION; its data files would not match the patched binary."
for tool in meson ninja pkg-config; do
  command -v "$tool" >/dev/null || fail "$tool is required (brew install meson ninja pkgconf)."
done

WORK_DIR="$OUT_DIR/.work"
SOURCE_DIR="$WORK_DIR/qemu-$QEMU_VERSION"
TARBALL="$WORK_DIR/qemu-$QEMU_VERSION.tar.xz"
mkdir -p "$WORK_DIR"

if [[ "$(shasum -a 256 "$TARBALL" 2>/dev/null | cut -d' ' -f1)" != "$QEMU_SHA256" ]]; then
  curl -sSfL "$QEMU_URL" -o "$TARBALL.download"
  [[ "$(shasum -a 256 "$TARBALL.download" | cut -d' ' -f1)" == "$QEMU_SHA256" ]] \
    || { rm -f "$TARBALL.download"; fail "qemu-$QEMU_VERSION.tar.xz did not match its pinned SHA-256."; }
  mv "$TARBALL.download" "$TARBALL"
fi

rm -rf "$SOURCE_DIR"
tar -xf "$TARBALL" -C "$WORK_DIR"
for patch_file in "$PATCH_DIR"/*.patch; do
  patch -s -p1 -d "$SOURCE_DIR" < "$patch_file"
done
# The same adjustment Homebrew makes: Python 3.15 no longer bundles `wheel`, and the build is offline.
sed -i '' '/^"wheel" = /d' "$SOURCE_DIR/pythondeps.toml"

CONFIGURE_OPTIONS=(
  --target-list=aarch64-softmmu
  --disable-bsd-user
  --disable-download
  --disable-guest-agent
  --disable-docs
  --disable-sdl
  --disable-gtk
  # ParavirtualizedGraphics.framework is present but unusable on current macOS; Homebrew disables it too.
  --disable-pvg
  --enable-hvf
  --enable-cocoa
  --enable-slirp
  --enable-zstd
  --enable-fdt=system
  --enable-capstone
  "--extra-cflags=-I$BREW_PREFIX/include"
  "--extra-ldflags=-L$BREW_PREFIX/lib"
)
(
  mkdir -p "$SOURCE_DIR/build"
  cd "$SOURCE_DIR/build"
  LIBTOOL=glibtool nice -n 15 ../configure "${CONFIGURE_OPTIONS[@]}" >configure.log 2>&1 \
    || { tail -20 configure.log >&2; exit 1; }
  nice -n 15 ninja qemu-system-aarch64 >build.log 2>&1 || { tail -20 build.log >&2; exit 1; }
) || fail "the QEMU build failed; logs are in $SOURCE_DIR/build."

rm -rf "$OUT_DIR/patches"
mkdir -p "$OUT_DIR/patches"
cp "$PATCH_DIR"/*.patch "$OUT_DIR/patches/"
cp "$SOURCE_DIR/build/qemu-system-aarch64" "$OUT_DIR/qemu-system-aarch64"
{
  echo "# Veil's patched qemu-system-aarch64"
  echo
  echo "- Source: $QEMU_URL (SHA-256 $QEMU_SHA256), GPL-2.0."
  echo "- Patches, applied in order with \`patch -p1\`:"
  for patch_file in "$PATCH_DIR"/*.patch; do
    echo "  - $(basename "$patch_file")"
  done
  echo "- Configure options: ${CONFIGURE_OPTIONS[*]}"
  echo "- Built with: $(cc --version | head -1); meson $(meson --version); ninja $(ninja --version)."
} >"$OUT_DIR/PROVENANCE.md"
echo "$STAMP" >"$OUT_DIR/.stamp"
