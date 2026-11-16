#!/usr/bin/env bash
# Builds Veil's own Secure Boot Arm UEFI firmware from TianoCore EDK2 so Windows 11 boots with
# Secure Boot without UTM or a distribution's firmware package.
#
#   script/build_secure_firmware.sh [output directory]   (default: dist/.secure-firmware)
#
# Output:
#   edk2-aarch64-secure-code.fd   ArmVirtQemu with SECURE_BOOT_ENABLE, padded to the 64 MiB pflash size
#   edk2-arm-secure-vars.fd       variable store with Microsoft's PK, KEK, and db certificates enrolled
#                                 and Secure Boot on; Veil pads its per-VM copy to 64 MiB
#   PROVENANCE.md                 the exact source, options, and tools used
#
# The recipe follows QEMU's roms/edk2-build.config for ArmVirtQemu-AARCH64 at the EDK2 commit QEMU
# 11.1 pins (UTM ships the same commit), plus SECURE_BOOT_ENABLE. Debian's builds of this platform
# stop at "Start boot option" with the Windows 11 Arm ISO; this one reaches Windows Setup.
#
# Needs: git, python3, and Homebrew llvm, lld, and acpica (brew install llvm lld acpica).
# The result is cached until this script changes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist/.secure-firmware}"
EDK2_REPOSITORY="https://github.com/tianocore/edk2.git"
EDK2_COMMIT="4dfdca63a93497203f197ec98ba20e2327e4afe4"
VIRT_FIRMWARE_VERSION="26.10"

STAMP="$(shasum "${BASH_SOURCE[0]}" | cut -c1-16)"
if [[ "$(cat "$OUT_DIR/.stamp" 2>/dev/null || true)" == "$STAMP" ]]; then
  exit 0
fi

fail() {
  echo "build_secure_firmware: $*" >&2
  exit 1
}

BREW_LLVM="$(brew --prefix llvm 2>/dev/null || true)"
BREW_LLD="$(brew --prefix lld 2>/dev/null || true)"
[[ -x "$BREW_LLVM/bin/clang" && -x "$BREW_LLD/bin/ld.lld" ]] || fail "Homebrew llvm and lld are required (brew install llvm lld acpica)."
command -v iasl >/dev/null || fail "iasl is required (brew install acpica)."

WORK_DIR="$OUT_DIR/.work"
EDK2_DIR="$WORK_DIR/edk2"
mkdir -p "$WORK_DIR"

if [[ "$(git -C "$EDK2_DIR" rev-parse HEAD 2>/dev/null || true)" != "$EDK2_COMMIT" ]]; then
  rm -rf "$EDK2_DIR"
  git init -q "$EDK2_DIR"
  git -C "$EDK2_DIR" fetch -q --depth 1 "$EDK2_REPOSITORY" "$EDK2_COMMIT"
  git -C "$EDK2_DIR" checkout -q FETCH_HEAD
  git -C "$EDK2_DIR" submodule update -q --init --depth 1
fi

(
  cd "$EDK2_DIR"
  export PATH="$BREW_LLVM/bin:$BREW_LLD/bin:$PATH"
  export PYTHON_COMMAND=python3
  export CLANGDWARF_BIN="$BREW_LLVM/bin/"
  # Apple clang warns that BaseTools redefines UINT8_MAX; the tools are fine.
  make -s -C BaseTools/Source/C EXTRA_OPTFLAGS="-Wno-error" >/dev/null
  set +u
  source edksetup.sh BaseTools >/dev/null
  set -u
  build -q -a AARCH64 -t CLANGDWARF -b RELEASE -p ArmVirtPkg/ArmVirtQemu.dsc -n "$(sysctl -n hw.ncpu)" \
    -D NETWORK_HTTP_BOOT_ENABLE -D NETWORK_IP6_ENABLE -D NETWORK_TLS_ENABLE \
    -D NETWORK_ISCSI_ENABLE -D NETWORK_ALLOW_HTTP_CONNECTIONS \
    -D TPM2_ENABLE -D TPM2_CONFIG_ENABLE -D TPM1_ENABLE -D CAVIUM_ERRATUM_27456 \
    -D SECURE_BOOT_ENABLE=TRUE -D DEBUG_PRINT_ERROR_LEVEL=0x80000000 \
    --pcd PcdDxeNxMemoryProtectionPolicy=0xC000000000007FD1 \
    --pcd PcdUninstallMemAttrProtocol=TRUE
) >"$WORK_DIR/build.log" 2>&1 || fail "EDK2 build failed; see $WORK_DIR/build.log."

FV_DIR="$EDK2_DIR/Build/ArmVirtQemu-AARCH64/RELEASE_CLANGDWARF/FV"

# virt-firmware enrolls the certificates. Its crypt_r dependency only serves the password helpers,
# and it does not build on newer Python, so the two libraries the enrollment needs are installed alone.
VENV="$WORK_DIR/virt-firmware"
if [[ ! -x "$VENV/bin/virt-fw-vars" ]]; then
  python3 -m venv "$VENV"
  {
    "$VENV/bin/pip" install --no-deps "virt-firmware==$VIRT_FIRMWARE_VERSION"
    "$VENV/bin/pip" install cryptography pefile
  } >"$WORK_DIR/pip.log" 2>&1 || fail "could not install virt-firmware; see $WORK_DIR/pip.log."
fi

rm -f "$OUT_DIR"/*.fd "$OUT_DIR/PROVENANCE.md" "$OUT_DIR/.stamp"
cp "$FV_DIR/QEMU_EFI.fd" "$OUT_DIR/edk2-aarch64-secure-code.fd"
truncate -s 64m "$OUT_DIR/edk2-aarch64-secure-code.fd"
"$VENV/bin/virt-fw-vars" -i "$FV_DIR/QEMU_VARS.fd" -o "$OUT_DIR/edk2-arm-secure-vars.fd" \
  --enroll-microsoft --microsoft-kek all --microsoft-db all --secure-boot >/dev/null 2>&1 \
  || fail "could not enroll the Microsoft Secure Boot certificates."

{
  echo "# Veil Secure Boot Arm UEFI firmware"
  echo
  echo "Built by script/build_secure_firmware.sh."
  echo
  echo "- Source: $EDK2_REPOSITORY at $EDK2_COMMIT (BSD-2-Clause-Patent; bundled OpenSSL is Apache-2.0)."
  echo "- Platform: ArmVirtPkg/ArmVirtQemu.dsc, AARCH64, RELEASE, CLANGDWARF ($("$BREW_LLVM/bin/clang" --version | head -1))."
  echo "- Options: QEMU's ArmVirtQemu-AARCH64 recipe (network, TPM 1.2/2.0, silent debug output, NX policy"
  echo "  0xC000000000007FD1, Memory Attribute Protocol uninstalled) plus SECURE_BOOT_ENABLE=TRUE."
  echo "- Variable store: virt-firmware $VIRT_FIRMWARE_VERSION \`--enroll-microsoft --microsoft-kek all --microsoft-db all --secure-boot\`:"
  "$VENV/bin/virt-fw-vars" -i "$OUT_DIR/edk2-arm-secure-vars.fd" --print --verbose 2>/dev/null \
    | awk '/subject CN=/{sub(/^ *subject /, ""); print "  - " $0}'
  echo "- dbx holds only a placeholder entry; Windows applies Microsoft's revocation list through Windows Update."
} >"$OUT_DIR/PROVENANCE.md"
cp "$EDK2_DIR/License.txt" "$OUT_DIR/edk2-License.txt"

echo "$STAMP" >"$OUT_DIR/.stamp"
