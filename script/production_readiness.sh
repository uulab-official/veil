#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKLIST_PATH="${VEIL_PRODUCTION_CHECKLIST:-$ROOT_DIR/docs/checklists/2026-08-05-production-readiness.md}"
CHECKLIST_ONLY=0
JSON=0
RUN_AUTOMATED=0

usage() {
  cat <<'USAGE'
usage: ./script/production_readiness.sh [options]

Evaluates the production checklist and refuses release-ready status while any
P0 item is unresolved. Automated tests never override missing live evidence.

Options:
  --checklist-only  Read the checklist without running automated tests.
  --run-automated   Run ./script/test_all.sh before making the decision.
  --json            Emit one machine-readable JSON object.
  --help            Show this help.

Environment:
  VEIL_PRODUCTION_CHECKLIST  Override the checklist path for a controlled test.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --checklist-only)
      CHECKLIST_ONLY=1
      ;;
    --run-automated)
      RUN_AUTOMATED=1
      ;;
    --json)
      JSON=1
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

if [[ "$CHECKLIST_ONLY" -eq 1 && "$RUN_AUTOMATED" -eq 1 ]]; then
  echo "--checklist-only and --run-automated cannot be used together." >&2
  exit 2
fi

if [[ ! -f "$CHECKLIST_PATH" ]]; then
  if [[ "$JSON" -eq 1 ]]; then
    printf '{"status":"blocked","releaseReady":false,"p0Total":0,"passingP0Count":0,"unresolvedP0Count":-1,"automatedGate":"not-run","reason":"checklist-not-found"}\n'
  else
    echo "Production readiness: BLOCKED"
    echo "Checklist not found: $CHECKLIST_PATH"
  fi
  exit 2
fi

read -r P0_TOTAL UNRESOLVED_P0 < <(
  awk '
    BEGIN { in_p0 = 0; total = 0; unresolved = 0 }
    /^## P0 / { in_p0 = 1; next }
    /^## / && in_p0 { exit }
    in_p0 && /^- \[[ xX]\] / {
      total++
      if ($0 ~ /^- \[ \] /) unresolved++
    }
    END { print total, unresolved }
  ' "$CHECKLIST_PATH"
)
PASSING_P0=$((P0_TOTAL - UNRESOLVED_P0))
AUTOMATED_GATE="not-run"

if [[ "$RUN_AUTOMATED" -eq 1 ]]; then
  AUTOMATED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/veil-production-readiness.XXXXXX")"
  trap 'rm -rf "$AUTOMATED_DIR"' EXIT
  if "$ROOT_DIR/script/test_all.sh" >"$AUTOMATED_DIR/test-all.log" 2>&1; then
    AUTOMATED_GATE="passed"
  else
    AUTOMATED_GATE="failed"
  fi
fi

RELEASE_READY=false
STATUS="blocked"
if [[ "$UNRESOLVED_P0" -eq 0 && "$AUTOMATED_GATE" == "passed" ]]; then
  RELEASE_READY=true
  STATUS="ready"
fi

if [[ "$JSON" -eq 1 ]]; then
  printf '{"status":"%s","releaseReady":%s,"p0Total":%d,"passingP0Count":%d,"unresolvedP0Count":%d,"automatedGate":"%s"}\n' \
    "$STATUS" "$RELEASE_READY" "$P0_TOTAL" "$PASSING_P0" "$UNRESOLVED_P0" "$AUTOMATED_GATE"
else
  echo "Production readiness: $(printf '%s' "$STATUS" | tr '[:lower:]' '[:upper:]')"
  echo "P0 checklist: $PASSING_P0/$P0_TOTAL passed; $UNRESOLVED_P0 unresolved"
  echo "Automated regression gate: $AUTOMATED_GATE"
  if [[ "$RELEASE_READY" == true ]]; then
    echo "Release decision: READY"
  else
    echo "Release decision: BLOCKED until every P0 item has fresh evidence and the automated gate passes."
  fi
fi

if [[ "$RELEASE_READY" == true ]]; then
  exit 0
fi
exit 2
