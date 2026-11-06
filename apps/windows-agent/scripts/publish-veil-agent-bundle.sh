#!/usr/bin/env bash
set -euo pipefail

configuration="Release"
runtime="win-arm64"
self_contained="true"
dotnet_bin="${DOTNET_BIN:-dotnet}"
build_id=""

usage() {
  cat <<'USAGE'
Usage: publish-veil-agent-bundle.sh [options]

Publishes the Veil Windows guest agent to apps/windows-agent/app so the
installer can run inside Windows without a guest-side .NET SDK.

Options:
  --configuration <name>     Build configuration. Default: Release
  --runtime <rid>            .NET runtime identifier. Default: win-arm64
  --framework-dependent      Publish without bundling the .NET runtime
  --dotnet <path>            Path to dotnet executable
  --build-id <id>            Report agentVersion 0.1.0+<id> and record it in
                             app/veil-agent-version.txt
  -h, --help                 Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      configuration="${2:?Missing value for --configuration}"
      shift 2
      ;;
    --runtime)
      runtime="${2:?Missing value for --runtime}"
      shift 2
      ;;
    --framework-dependent)
      self_contained="false"
      shift
      ;;
    --dotnet)
      dotnet_bin="${2:?Missing value for --dotnet}"
      shift 2
      ;;
    --build-id)
      build_id="${2:?Missing value for --build-id}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
agent_root="$(cd -- "$script_dir/.." && pwd)"
project_path="$agent_root/src/VeilAgent/VeilAgent.csproj"
bundle_root="$agent_root/app"
backup_root="$agent_root/app.previous"
lock_root="$agent_root/.app-publish.lock"
staging_root=""

if ! command -v "$dotnet_bin" >/dev/null 2>&1; then
  echo "dotnet was not found. Install the .NET 8 SDK or pass --dotnet /path/to/dotnet." >&2
  exit 69
fi

# Refuse surprising targets before changing anything. All managed directories are siblings on the
# same filesystem, so promotion uses renames instead of copying onto a live bundle.
for target in "$bundle_root" "$backup_root"; do
  if [[ -L "$target" || ( -e "$target" && ! -d "$target" ) ]]; then
    echo "Refusing non-directory or symlink bundle target: $target" >&2
    exit 73
  fi
done

if ! mkdir "$lock_root" 2>/dev/null; then
  echo "Another publish is active or needs recovery: $lock_root. Check owner.pid before removing a stale lock." >&2
  exit 75
fi

cleanup_publish() {
  local publish_status=$?
  local preserve_staging=0
  trap - EXIT HUP INT TERM
  # If promotion failed after retiring the current bundle, put that exact bundle back. Never delete
  # the last good copy when rollback itself fails; leave its location visible for manual recovery.
  if [[ -n "$staging_root" && -d "$staging_root/previous" ]]; then
    if [[ ! -e "$bundle_root" && ! -L "$bundle_root" ]] && mv "$staging_root/previous" "$bundle_root"; then
      echo "Restored the previous VeilAgent bundle after failed promotion." >&2
    else
      preserve_staging=1
      echo "Previous bundle retained for recovery at $staging_root/previous" >&2
    fi
  fi
  if [[ -n "$staging_root" && "$preserve_staging" -eq 0 ]]; then
    rm -rf "$staging_root"
  fi
  rm -f "$lock_root/owner.pid"
  rmdir "$lock_root"
  exit "$publish_status"
}
trap cleanup_publish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' "$$" > "$lock_root/owner.pid"
staging_root="$(mktemp -d "$agent_root/.app-publish.XXXXXXXX")"
mkdir "$staging_root/next"

version_args=()
if [[ -n "$build_id" ]]; then
  version_args=("-p:InformationalVersion=0.1.0+$build_id")
fi

"$dotnet_bin" publish "$project_path" \
  --configuration "$configuration" \
  --runtime "$runtime" \
  --self-contained "$self_contained" \
  -p:EnableWindowsTargeting=true \
  ${version_args[@]+"${version_args[@]}"} \
  --output "$staging_root/next"

if [[ -n "$build_id" ]]; then
  printf '%s\n' "0.1.0+$build_id" > "$staging_root/next/veil-agent-version.txt"
fi

for artifact in VeilAgent.exe VeilAgent.dll VeilAgent.deps.json VeilAgent.runtimeconfig.json; do
  if [[ ! -f "$staging_root/next/$artifact" || ! -s "$staging_root/next/$artifact" || -L "$staging_root/next/$artifact" ]]; then
    echo "dotnet publish did not produce a complete bundle: missing or empty $artifact." >&2
    exit 70
  fi
done

if [[ -d "$bundle_root" ]]; then
  mv "$bundle_root" "$staging_root/previous"
fi
mv "$staging_root/next" "$bundle_root"

if [[ -d "$staging_root/previous" ]]; then
  # Rotate the older backup only after the new bundle has been fully published and promoted.
  if [[ -d "$backup_root" ]]; then
    rm -rf "$backup_root"
  fi
  mv "$staging_root/previous" "$backup_root"
  echo "Previous VeilAgent bundle retained at $backup_root."
fi

echo "VeilAgent bundle published to $bundle_root."
echo "Run Install Veil Agent.cmd from the VEIL_AUTO media inside Windows to install without the .NET SDK."
