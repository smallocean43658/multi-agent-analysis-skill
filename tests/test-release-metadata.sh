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

require_contains README.md "Cross-Review Gate"
require_contains MAINTENANCE.md "target_id"

if grep -Eq "Local install (path|type):" "$REPO_ROOT/MAINTENANCE.md"; then
  echo "MAINTENANCE.md should not contain machine-local install fields" >&2
  exit 1
fi

echo "release metadata looks good"
