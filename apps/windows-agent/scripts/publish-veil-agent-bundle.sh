#!/usr/bin/env bash
set -euo pipefail

configuration="Release"
runtime="win-arm64"
self_contained="true"
dotnet_bin="${DOTNET_BIN:-dotnet}"

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

if ! command -v "$dotnet_bin" >/dev/null 2>&1; then
  echo "dotnet was not found. Install the .NET 8 SDK or pass --dotnet /path/to/dotnet." >&2
  exit 69
fi

rm -rf "$bundle_root"
mkdir -p "$bundle_root"

"$dotnet_bin" publish "$project_path" \
  --configuration "$configuration" \
  --runtime "$runtime" \
  --self-contained "$self_contained" \
  -p:EnableWindowsTargeting=true \
  --output "$bundle_root"

agent_exe="$bundle_root/VeilAgent.exe"
if [[ ! -f "$agent_exe" ]]; then
  echo "dotnet publish completed, but VeilAgent.exe was not found at $agent_exe." >&2
  exit 70
fi

echo "VeilAgent bundle published to $bundle_root."
echo "Run Install Veil Agent.cmd from the VEIL_AUTO media inside Windows to install without the .NET SDK."
