#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_WINDOWS_AGENT=0
SKIP_APP_VERIFY=0
SKIP_NODE_INSTALL=0
LIST_ONLY=0

usage() {
  cat <<'USAGE'
usage: ./script/test_all.sh [options]

Runs the complete local Veil regression gate. Required tools are checked before
any test starts, so a partial run cannot be mistaken for a passing full gate.

Options:
  --list                 List every discovered test package without running it.
  --skip-windows-agent   Skip .NET Windows agent tests with an explicit notice.
  --skip-app-verify      Skip the macOS signed app launch verification.
  --skip-node-install    Do not run npm ci for packages with lockfiles.
  --help                 Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      LIST_ONLY=1
      ;;
    --skip-windows-agent)
      SKIP_WINDOWS_AGENT=1
      ;;
    --skip-app-verify)
      SKIP_APP_VERIFY=1
      ;;
    --skip-node-install)
      SKIP_NODE_INSTALL=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

test_package_files() {
  find "$ROOT_DIR/packages/protocol" "$ROOT_DIR/harness" \
    -path '*/node_modules' -prune -o \
    -name package.json -type f -print \
    | sort \
    | while IFS= read -r package_file; do
        if grep -Eq '"test"[[:space:]]*:' "$package_file"; then
          printf '%s\n' "$package_file"
        fi
      done
}

relative_path() {
  printf '%s' "${1#"$ROOT_DIR/"}"
}

list_gate() {
  echo "Swift: apps/mac-host"
  if [[ "$SKIP_WINDOWS_AGENT" -eq 1 ]]; then
    echo "Windows agent: skipped by --skip-windows-agent"
  else
    echo "Windows agent: apps/windows-agent/tests/VeilAgent.Tests"
  fi
  echo "Node test packages:"
  while IFS= read -r package_file; do
    echo "  - $(relative_path "$(dirname "$package_file")")"
  done < <(test_package_files)
  if [[ "$(uname -s)" == "Darwin" && "$SKIP_APP_VERIFY" -eq 0 ]]; then
    echo "macOS app: ./script/build_and_run.sh --verify + ./script/test_macos_lifecycle.sh --skip-build"
  else
    echo "macOS app: skipped"
  fi
}

require_command() {
  local command_name="$1"
  local install_hint="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Regression gate blocked: missing required command '$command_name'. $install_hint" >&2
    return 1
  fi
}

preflight() {
  local blocked=0
  require_command swift "Install the current Xcode command-line tools." || blocked=1
  require_command node "Install a supported Node.js runtime." || blocked=1
  require_command npm "Install npm alongside Node.js." || blocked=1

  if [[ "$SKIP_WINDOWS_AGENT" -eq 0 ]]; then
    require_command dotnet "Install the .NET 8 SDK or rerun with --skip-windows-agent." || blocked=1
  fi

  if [[ "$(uname -s)" == "Darwin" && "$SKIP_APP_VERIFY" -eq 0 ]]; then
    require_command codesign "Install the current Xcode command-line tools." || blocked=1
    require_command plutil "Use a supported macOS development host." || blocked=1
    require_command ditto "Use a supported macOS development host." || blocked=1
    require_command xattr "Use a supported macOS development host." || blocked=1
  fi

  if [[ "$blocked" -ne 0 ]]; then
    echo "No tests were run because regression-gate prerequisites are incomplete." >&2
    return 1
  fi
}

run_node_tests() {
  local package_count=0
  while IFS= read -r package_file; do
    local package_dir
    package_dir="$(dirname "$package_file")"
    package_count=$((package_count + 1))
    echo "==> Node: $(relative_path "$package_dir")"
    if [[ "$SKIP_NODE_INSTALL" -eq 0 && -f "$package_dir/package-lock.json" ]]; then
      npm --prefix "$package_dir" ci
    fi
    npm --prefix "$package_dir" test
  done < <(test_package_files)

  if [[ "$package_count" -eq 0 ]]; then
    echo "Regression gate failed: no Node test packages were discovered." >&2
    return 1
  fi
  echo "Node test packages passed: $package_count"
}

if [[ "$LIST_ONLY" -eq 1 ]]; then
  list_gate
  exit 0
fi

preflight

echo "==> Swift host"
swift test --disable-sandbox --package-path "$ROOT_DIR/apps/mac-host"

if [[ "$SKIP_WINDOWS_AGENT" -eq 1 ]]; then
  echo "==> Windows agent skipped by explicit request"
else
  echo "==> Windows agent"
  dotnet test "$ROOT_DIR/apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj"
fi

run_node_tests

if [[ "$(uname -s)" == "Darwin" && "$SKIP_APP_VERIFY" -eq 0 ]]; then
  echo "==> macOS app bundle and launch contract"
  "$ROOT_DIR/script/build_and_run.sh" --verify
  echo "==> macOS app install and uninstall lifecycle"
  "$ROOT_DIR/script/test_macos_lifecycle.sh" --skip-build
else
  echo "==> macOS app verification skipped"
fi

echo "All requested Veil regression gates passed."
