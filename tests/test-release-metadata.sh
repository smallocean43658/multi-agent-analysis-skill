#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

require_contains() {
  local path="$1"
  local pattern="$2"
  if ! grep -Fq -- "$pattern" "$REPO_ROOT/$path"; then
    echo "$path must contain: $pattern" >&2
    exit 1
  fi
}

require_absent() {
  local path="$1"
  local pattern="$2"
  if grep -Fiq -- "$pattern" "$REPO_ROOT/$path"; then
    echo "$path must not contain: $pattern" >&2
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
require_contains README.md "B1-B6"
require_contains MAINTENANCE.md "decision-chain-b1-b6-v1"
require_contains README.md 'fixed B1-B6 dimensions for `review`'
require_contains README.md 'target-adaptive D1-D6 lenses for `divergent-analysis`'

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

mapfile -t public_markdown_files < <(git -C "$REPO_ROOT" ls-files -- '*.md')
if [[ "${#public_markdown_files[@]}" -eq 0 ]]; then
  echo "release metadata must scan tracked Markdown guidance" >&2
  exit 1
fi

historical_plan="docs/superpowers/plans/2026-07-04-adaptive-divergent-cross-review.md"
if git -C "$REPO_ROOT" ls-files --error-unmatch "$historical_plan" >/dev/null 2>&1; then
  echo "historical classic review plan must not remain tracked" >&2
  exit 1
fi

decision_chain_dimensions=(
  "Goal And Requirement Alignment"
  "Mechanism And Structural Validity"
  "Evidence And Uncertainty Audit"
  "Alternatives And Decision Value"
  "Risk And Robustness"
  "Execution And Lifecycle"
)
for dimension in "${decision_chain_dimensions[@]}"; do
  require_contains README.md "$dimension"
done

review_table_rows="$(grep -Ec '^\| B[1-6] \|' "$REPO_ROOT/SKILL.md" || true)"
if [[ "$review_table_rows" -ne 6 ]]; then
  echo "SKILL.md must contain exactly six B1-B6 review rows" >&2
  exit 1
fi

if grep -Eq '^\| A[1-6] \|' "$REPO_ROOT/SKILL.md"; then
  echo "SKILL.md must not expose a second complete classic review table" >&2
  exit 1
fi

public_contract_files=("${public_markdown_files[@]}" test-prompts.json)
for path in "${public_contract_files[@]}"; do
  require_absent "$path" "A1-A6"
  require_absent "$path" "candidate"
  require_absent "$path" "experiment"
  require_absent "$path" "A/B"
  require_absent "$path" "portfolio"
  require_absent "$path" "--review-portfolio"
done

for path in "${public_markdown_files[@]}"; do
  if grep -Eq '(^|[^[:alnum:]_])A[1-6]([^[:alnum:]_]|$)' "$REPO_ROOT/$path"; then
    echo "$path must not expose classic A1-A6 review slot guidance" >&2
    exit 1
  fi
done

if grep -Eq 'resume_agent|send_input|prefer-resume|attempts\[\]' "$REPO_ROOT/scripts/run-ledger"; then
  echo "production worker reuse is not part of this release" >&2
  exit 1
fi

echo "release metadata looks good"
