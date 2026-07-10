#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

require_contains() {
  local path="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$REPO_ROOT/$path"; then
    echo "$path must contain: $pattern" >&2
    exit 1
  fi
}

[[ -f "$REPO_ROOT/LICENSE" ]] || {
  echo "public repository must include LICENSE" >&2
  exit 1
}

require_contains LICENSE "Permission is granted to use and modify"
require_contains LICENSE "Publishing or redistribution is not permitted"
require_contains README.md "Python >= 3.10"
require_contains README.md "Bash >= 4"
require_contains README.md "macOS"
require_contains README.md "Smoke tests do not exercise live multi-agent tool calls"
require_contains MAINTENANCE.md "Python >= 3.10"
require_contains MAINTENANCE.md "Bash >= 4"
require_contains README.md "target-adaptive"
require_contains README.md "adaptive-backlog-v1"
require_contains README.md "1-6 fresh follow-up workers"
require_contains README.md "pending backlog"
require_contains README.md "engineering overlay"
require_contains README.md "objective_alignment"
require_contains README.md "First Principles"

require_contains README.md "Cross-Review Gate"
require_contains MAINTENANCE.md "target_id"

if grep -Fq "Exactly six workers are required for a valid skill round." "$REPO_ROOT/MAINTENANCE.md"; then
  echo "MAINTENANCE.md must distinguish adaptive follow-up batch size" >&2
  exit 1
fi
require_contains MAINTENANCE.md "Round 1 and legacy protocol rounds use six workers; adaptive follow-up batches use 1-6."

if grep -Eq "Local install (path|type):" "$REPO_ROOT/MAINTENANCE.md"; then
  echo "MAINTENANCE.md should not contain machine-local install fields" >&2
  exit 1
fi

forbidden_tracked="$(git -C "$REPO_ROOT" ls-files | grep -E '(^|/)(\.superpowers|\.local-maintenance|\.darwin|__pycache__)(/|$)|\.pyc$' || true)"
if [[ -n "$forbidden_tracked" ]]; then
  echo "tracked operational or private files are forbidden:" >&2
  echo "$forbidden_tracked" >&2
  exit 1
fi

require_contains README.md "classic A1-A6"
require_contains MAINTENANCE.md "classic A1-A6"

selected_portfolio_lenses=(
  "First Principles"
  "Occam's Razor"
  "Bounded Bayesian"
  "Expected Cost Optimality"
  "Adversarial Review"
  "Execution Friction"
)
for lens in "${selected_portfolio_lenses[@]}"; do
  require_contains README.md "$lens"
done

if grep -Eq 'resume_agent|send_input|prefer-resume|attempts\[\]' "$REPO_ROOT/scripts/run-ledger"; then
  echo "production worker reuse is not part of this release" >&2
  exit 1
fi

echo "release metadata looks good"
