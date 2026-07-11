#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="$REPO_ROOT/scripts/run-ledger"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

case_name() {
  printf 'case: %s\n' "$1"
}

expect_failpoint() {
  local failpoint="$1"
  shift
  set +e
  RUN_LEDGER_FAILPOINT="$failpoint" "$@" >"$tmpdir/failpoint.out" 2>"$tmpdir/failpoint.err"
  local status=$?
  set -e
  [[ $status -eq 97 ]] || {
    cat "$tmpdir/failpoint.err" >&2
    fail "$failpoint should exit 97, got $status"
  }
}

expect_failure() {
  if "$@" >"$tmpdir/conflict.out" 2>"$tmpdir/conflict.err"; then
    fail "command should have failed: $*"
  fi
}

expect_failure_matching() {
  local expected="$1"
  shift
  if "$@" >"$tmpdir/expected-failure.out" 2>"$tmpdir/expected-failure.err"; then
    fail "command should have failed with $expected: $*"
  fi
  if ! grep -Fq "$expected" "$tmpdir/expected-failure.err"; then
    cat "$tmpdir/expected-failure.err" >&2
    fail "command failure did not contain $expected: $*"
  fi
}

canonical_snapshot() {
  local run_dir="$1"
  find "$run_dir" -maxdepth 1 -type f \
    \( -name 'state.json' -o -name 'round-*.json' -o -name 'round-*.md' -o -name 'ledger.md' \) \
    -print0 | sort -z | xargs -0 sha256sum
}

expect_failure_unchanged() {
  local expected="$1"
  local run_dir="$2"
  shift 2
  local before
  local after
  before="$(canonical_snapshot "$run_dir")"
  expect_failure_matching "$expected" "$@"
  after="$(canonical_snapshot "$run_dir")"
  [[ "$before" == "$after" ]] || fail "rejected command mutated canonical files in $run_dir"
}

init_run() {
  local root="$1"
  local title="$2"
  local run_dir
  run_dir="$("$LEDGER" init \
    --root "$root" \
    --mode review \
    --target docs/plan.md \
    --objective "Verify deterministic ledger recovery" \
    --spawn-tool multi_agent_v1.spawn_agent \
    --wait-tool multi_agent_v1.wait_agent \
    --close-tool multi_agent_v1.close_agent \
    --cwd "$REPO_ROOT" \
    --title "$title")"
  python3 - "$run_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state.pop("protocol_version", None)
state.pop("review_portfolio_version", None)
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
  printf '%s\n' "$run_dir"
}

init_b_run() {
  local root="$1"
  local title="$2"
  "$LEDGER" init \
    --root "$root" \
    --mode review \
    --target docs/plan.md \
    --objective "Verify B portfolio recovery" \
    --spawn-tool multi_agent_v1.spawn_agent \
    --wait-tool multi_agent_v1.wait_agent \
    --close-tool multi_agent_v1.close_agent \
    --cwd "$REPO_ROOT" \
    --title "$title"
}

event_count() {
  local round_json="$1"
  local event="$2"
  local slot="$3"
  python3 - "$round_json" "$event" "$slot" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(
    sum(
        1
        for item in round_doc.get("events", [])
        if item.get("event") == sys.argv[2] and item.get("slot") == sys.argv[3]
    )
)
PY
}

six="$tmpdir/six.json"
cat >"$six" <<'JSON'
[
  {"slot": "A1", "lens": "First Principles", "question": "What assumptions must hold?"},
  {"slot": "A2", "lens": "Occam's Razor", "question": "What can be simplified?"},
  {"slot": "A3", "lens": "Bounded Bayesian", "question": "What would update confidence?"},
  {"slot": "A4", "lens": "Expected Cost Optimality", "question": "What is the expected cost of being wrong?"},
  {"slot": "A5", "lens": "Adversarial Review", "question": "How can this break?"},
  {"slot": "A6", "lens": "Execution Friction", "question": "What makes this hard to use or maintain?"}
]
JSON

different_six="$tmpdir/different-six.json"
python3 - "$six" "$different_six" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload[0]["question"] = "Which different assumptions must hold?"
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

b_six="$tmpdir/b-six.json"
cat >"$b_six" <<'JSON'
[
  {"slot": "B1", "lens": "Goal And Requirement Alignment", "question": "What objective, requirements, and constraints must this satisfy?"},
  {"slot": "B2", "lens": "Mechanism And Structural Validity", "question": "What causal mechanism and structural boundaries make this viable?"},
  {"slot": "B3", "lens": "Evidence And Uncertainty Audit", "question": "What evidence, assumptions, and falsification conditions matter?"},
  {"slot": "B4", "lens": "Alternatives And Decision Value", "question": "Which alternatives, costs, and reversibility tradeoffs change the decision?"},
  {"slot": "B5", "lens": "Risk And Robustness", "question": "Which hostile conditions, failures, and recovery paths matter?"},
  {"slot": "B6", "lens": "Execution And Lifecycle", "question": "What delivery, testing, operations, and ownership work is required?"}
]
JSON

case_name "numeric round filenames must be canonical before reconciliation"
noncanonical_run="$(init_run "$tmpdir/noncanonical-root" "Noncanonical round filename")"
"$LEDGER" prepare-round --run-dir "$noncanonical_run" --round 1 --assignments "$six" >/dev/null
cp "$noncanonical_run/round-01.json" "$noncanonical_run/round-1.json"
expect_failure_unchanged "noncanonical round JSON filename" "$noncanonical_run" \
  "$LEDGER" status --run-dir "$noncanonical_run"

case_name "malformed static state is rejected before status reconciliation"
malformed_mode_run="$(init_b_run "$tmpdir/malformed-mode-root" "Malformed mode")"
"$LEDGER" prepare-round --run-dir "$malformed_mode_run" --round 1 --assignments "$b_six" >/dev/null
python3 - "$malformed_mode_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state["mode"] = "comparison"
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_unchanged "unsupported run mode" "$malformed_mode_run" \
  "$LEDGER" status --run-dir "$malformed_mode_run"

case_name "unknown review portfolio is rejected before lifecycle reconciliation"
unknown_portfolio_run="$(init_b_run "$tmpdir/unknown-portfolio-root" "Unknown portfolio")"
"$LEDGER" prepare-round --run-dir "$unknown_portfolio_run" --round 1 --assignments "$b_six" >/dev/null
python3 - "$unknown_portfolio_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state["review_portfolio_version"] = "unknown-review-v9"
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_unchanged "unsupported review portfolio" "$unknown_portfolio_run" \
  "$LEDGER" plan-dispatch --run-dir "$unknown_portfolio_run" --round 1 --slot B1

case_name "divergent mode rejects a review portfolio before reconciliation"
mode_field_run="$(init_b_run "$tmpdir/mode-field-root" "Mode field mismatch")"
python3 - "$mode_field_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state["mode"] = "divergent-analysis"
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_unchanged "divergent-analysis state must not include review_portfolio_version" \
  "$mode_field_run" "$LEDGER" status --run-dir "$mode_field_run"

case_name "state and canonical round mode mismatch is rejected without mutation"
round_mode_run="$(init_b_run "$tmpdir/round-mode-root" "Round mode mismatch")"
"$LEDGER" prepare-round --run-dir "$round_mode_run" --round 1 --assignments "$b_six" >/dev/null
python3 - "$round_mode_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc["mode"] = "divergent-analysis"
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_unchanged "round-01 mode conflicts with state" "$round_mode_run" \
  "$LEDGER" status --run-dir "$round_mode_run"

case_name "state and canonical Round 1 portfolio mismatch is rejected without mutation"
portfolio_mismatch_run="$(init_run "$tmpdir/portfolio-mismatch-root" "Portfolio mismatch")"
"$LEDGER" prepare-round --run-dir "$portfolio_mismatch_run" --round 1 --assignments "$six" >/dev/null
python3 - "$portfolio_mismatch_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state["review_portfolio_version"] = "decision-chain-b1-b6-v1"
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_unchanged "state review portfolio conflicts with canonical Round 1" \
  "$portfolio_mismatch_run" "$LEDGER" status --run-dir "$portfolio_mismatch_run"

case_name "B identity is restored from canonical Round 1 and exact replay remains stable"
b_recovery_run="$(init_b_run "$tmpdir/b-recovery-root" "B identity recovery")"
expect_failpoint "prepare-round:after-round-json" \
  "$LEDGER" prepare-round --run-dir "$b_recovery_run" --round 1 --assignments "$b_six"
python3 - "$b_recovery_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state.pop("review_portfolio_version")
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
b_round_before="$(sha256sum "$b_recovery_run/round-01.json")"
"$LEDGER" status --run-dir "$b_recovery_run" >/dev/null
python3 - "$b_recovery_run/state.json" "$b_recovery_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
expected = "decision-chain-b1-b6-v1"
if state.get("review_portfolio_version") != expected:
    raise SystemExit("status must restore B identity from canonical Round 1")
if round_doc.get("review_portfolio_version") != expected:
    raise SystemExit("B Round 1 must carry canonical portfolio identity")
PY
[[ "$b_round_before" == "$(sha256sum "$b_recovery_run/round-01.json")" ]] || \
  fail "B identity recovery mutated canonical Round 1"
"$LEDGER" prepare-round --run-dir "$b_recovery_run" --round 1 --assignments "$b_six" >/dev/null
[[ "$b_round_before" == "$(sha256sum "$b_recovery_run/round-01.json")" ]] || \
  fail "B exact prepare replay mutated canonical Round 1"

case_name "exact B assignments recover identity when the canonical field is absent"
b_assignment_recovery_run="$(init_b_run "$tmpdir/b-assignment-recovery-root" "B assignment recovery")"
"$LEDGER" prepare-round --run-dir "$b_assignment_recovery_run" --round 1 \
  --assignments "$b_six" >/dev/null
python3 - "$b_assignment_recovery_run/state.json" \
  "$b_assignment_recovery_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    payload.pop("review_portfolio_version")
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
b_assignment_round_before="$(sha256sum "$b_assignment_recovery_run/round-01.json")"
"$LEDGER" status --run-dir "$b_assignment_recovery_run" >/dev/null
python3 - "$b_assignment_recovery_run/state.json" "$b_assignment_recovery_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if state.get("review_portfolio_version") != "decision-chain-b1-b6-v1":
    raise SystemExit("exact B assignments must restore missing state identity")
if "review_portfolio_version" in round_doc:
    raise SystemExit("assignment-based recovery must not rewrite canonical Round 1")
if state.get("version") != 1 or round_doc.get("version") != 1:
    raise SystemExit("B assignment recovery must preserve schema version 1")
if state.get("protocol_version") != "adaptive-backlog-v1":
    raise SystemExit("B assignment recovery must preserve adaptive-backlog-v1")
PY
[[ "$b_assignment_round_before" == "$(sha256sum "$b_assignment_recovery_run/round-01.json")" ]] || \
  fail "assignment-based B identity recovery mutated canonical Round 1"

case_name "fieldless review state retains classic A slots during reconciliation"
portfolio_compat_run="$(init_run "$tmpdir/portfolio-compat-root" "Fieldless portfolio fixture")"
"$LEDGER" prepare-round --run-dir "$portfolio_compat_run" --round 1 --assignments "$six" >/dev/null
expect_failure "$LEDGER" prepare-round --run-dir "$portfolio_compat_run" --round 1 --assignments "$b_six"
"$LEDGER" status --run-dir "$portfolio_compat_run" >/dev/null
python3 - "$portfolio_compat_run/state.json" "$portfolio_compat_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if "review_portfolio_version" in state:
    raise SystemExit("status reconciliation must not write a portfolio onto a fieldless review state")
if [item["slot"] for item in round_doc["assignments"]] != ["A1", "A2", "A3", "A4", "A5", "A6"]:
    raise SystemExit("fieldless review state must retain classic A assignments")
PY

synthesis="$tmpdir/synthesis.json"
cat >"$synthesis" <<'JSON'
{
  "convergence": ["Recovery is deterministic."],
  "disagreement": [],
  "critical_disagreements": [],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Keep round JSON canonical."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [],
  "cross_review_outcomes": [],
  "expected_value_of_another_round": "No additional round is needed.",
  "objective_alignment": {
    "status": "aligned",
    "rationale": "The synthesis satisfies the recovery-test objective.",
    "unmet_requirements": []
  },
  "next_round_decision": "stop",
  "stop_reason": "The recovery contract is covered.",
  "next_round_question": ""
}
JSON

corrected_synthesis="$tmpdir/corrected-synthesis.json"
python3 - "$synthesis" "$corrected_synthesis" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload["convergence"] = ["Canonical round JSON makes recovery deterministic."]
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

legacy_partial_synthesis="$tmpdir/legacy-partial-synthesis.json"
cat >"$legacy_partial_synthesis" <<'JSON'
{
  "convergence": ["Recovery is deterministic."],
  "action_list": ["Keep round JSON canonical."],
  "expected_value_of_another_round": "No additional round is needed.",
  "objective_alignment": {
    "status": "aligned",
    "rationale": "The synthesis satisfies the recovery-test objective.",
    "unmet_requirements": []
  }
}
JSON

case_name "base-format synthesis state requires its persisted timestamp"
legacy_missing_timestamp_root="$tmpdir/legacy-missing-timestamp-root"
legacy_missing_timestamp_run="$(init_run \
  "$legacy_missing_timestamp_root" "Legacy synthesis without timestamp")"
"$LEDGER" prepare-round \
  --run-dir "$legacy_missing_timestamp_run" --round 1 --assignments "$six" >/dev/null
python3 - "$legacy_missing_timestamp_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("events", None)
round_doc.pop("updated_at", None)
round_doc["synthesis"]["convergence"] = ["Persisted synthesis without a timestamp."]
round_doc["synthesis"]["action_list"] = ["Reject ambiguous legacy evidence."]
round_doc["synthesis"]["expected_value_of_another_round"] = "Unknown without provenance."
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_matching "missing synthesis_recorded_at" \
  "$LEDGER" status --run-dir "$legacy_missing_timestamp_run"

case_name "base-format finalized rounds reject incomplete lifecycle"
legacy_incomplete_terminal_run="$(init_run \
  "$tmpdir/legacy-incomplete-terminal-root" "Legacy incomplete terminal round")"
"$LEDGER" prepare-round \
  --run-dir "$legacy_incomplete_terminal_run" --round 1 --assignments "$six" >/dev/null
python3 - "$legacy_incomplete_terminal_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("events", None)
round_doc.pop("updated_at", None)
round_doc["status"] = "finalized"
round_doc["synthesis"].update(
    {
        "convergence": ["Contradictory terminal state."],
        "action_list": ["Reject it."],
        "expected_value_of_another_round": "None.",
        "next_round_decision": "stop",
        "stop_reason": "Lifecycle never completed.",
    }
)
round_doc["synthesis_recorded_at"] = "2026-01-01T00:00:01+00:00"
round_doc["finalized_at"] = "2026-01-01T00:00:02+00:00"
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_matching "finalized lifecycle is incomplete" \
  "$LEDGER" status --run-dir "$legacy_incomplete_terminal_run"

case_name "base-format finalized rounds reject unready synthesis"
legacy_unready_terminal_run="$(init_run \
  "$tmpdir/legacy-unready-terminal-root" "Legacy unready terminal round")"
"$LEDGER" prepare-round \
  --run-dir "$legacy_unready_terminal_run" --round 1 --assignments "$six" >/dev/null
for slot in A1 A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn \
    --run-dir "$legacy_unready_terminal_run" --round 1 --slot "$slot" \
    --agent-id "unready-$slot" --status spawned >/dev/null
  "$LEDGER" record-result \
    --run-dir "$legacy_unready_terminal_run" --round 1 --slot "$slot" \
    --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close \
    --run-dir "$legacy_unready_terminal_run" --round 1 --slot "$slot" --status closed >/dev/null
done
python3 - "$legacy_unready_terminal_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("updated_at", None)
round_doc["events"] = [
    {key: value for key, value in event.items() if key != "event_id"}
    for event in round_doc["events"]
    if event["event"] in {"spawn", "result", "close"}
]
round_doc["status"] = "finalized"
round_doc["synthesis"]["next_round_decision"] = "stop"
round_doc["synthesis"]["stop_reason"] = "Synthesis was never ready."
round_doc["synthesis_recorded_at"] = "2026-01-01T00:00:01+00:00"
round_doc["finalized_at"] = "2026-01-01T00:00:02+00:00"
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_matching "finalized synthesis is not ready" \
  "$LEDGER" status --run-dir "$legacy_unready_terminal_run"

case_name "base-format terminal rounds backfill every canonical event"
legacy_terminal_root="$tmpdir/legacy-terminal-root"
legacy_terminal_run="$(init_run "$legacy_terminal_root" "Legacy terminal fixture")"
"$LEDGER" prepare-round \
  --run-dir "$legacy_terminal_run" --round 1 --assignments "$six" >/dev/null
for slot in A1 A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn \
    --run-dir "$legacy_terminal_run" --round 1 --slot "$slot" \
    --agent-id "legacy-$slot" --status spawned >/dev/null
  "$LEDGER" record-result \
    --run-dir "$legacy_terminal_run" --round 1 --slot "$slot" \
    --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close \
    --run-dir "$legacy_terminal_run" --round 1 --slot "$slot" --status closed >/dev/null
done
"$LEDGER" record-synthesis \
  --run-dir "$legacy_terminal_run" --round 1 --synthesis "$legacy_partial_synthesis" >/dev/null
"$LEDGER" finalize-round \
  --run-dir "$legacy_terminal_run" --round 1 --decision stop \
  --summary "The recovery contract is covered." >/dev/null
python3 - "$legacy_terminal_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("updated_at", None)
round_doc["events"] = [
    {key: value for key, value in event.items() if key != "event_id"}
    for event in round_doc["events"]
    if event["event"] in {"spawn", "result", "close"}
]
round_doc["synthesis"].pop("objective_alignment")
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY

legacy_terminal_timestamp="$tmpdir/legacy-terminal-synthesis-timestamp"
python3 - "$legacy_terminal_run/round-01.json" "$legacy_terminal_timestamp" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
timestamp = round_doc.pop("synthesis_recorded_at")
Path(sys.argv[2]).write_text(timestamp + "\n", encoding="utf-8")
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
expect_failure_matching "missing synthesis_recorded_at" \
  "$LEDGER" status --run-dir "$legacy_terminal_run"
python3 - "$legacy_terminal_run/round-01.json" "$legacy_terminal_timestamp" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc["synthesis_recorded_at"] = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY

legacy_terminal_snapshot="$tmpdir/legacy-terminal-snapshot.json"
legacy_terminal_status="$($LEDGER status --run-dir "$legacy_terminal_run")"
python3 - \
  "$legacy_terminal_status" \
  "$legacy_terminal_run/round-01.json" \
  "$legacy_terminal_snapshot" <<'PY'
import json
import sys
from pathlib import Path

status = json.loads(sys.argv[1])
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if status["status"] != "complete" or status["next_action"] != "complete":
    raise SystemExit("status did not reconcile the base-format terminal fixture")
if "objective_alignment" in round_doc["synthesis"]:
    raise SystemExit("legacy recovery must not invent objective_alignment")
events = round_doc["events"]
if len(events) != 21:
    raise SystemExit(f"expected 21 backfilled terminal events, got {len(events)}")
if events[0]["event_id"] != "r01-round-prepare":
    raise SystemExit("terminal fixture is missing its deterministic prepare event")
synthesis = [item for item in events if item["event"] == "synthesis"]
if len(synthesis) != 1 or not synthesis[0]["event_id"].startswith("r01-round-synthesis-"):
    raise SystemExit("terminal fixture is missing its deterministic synthesis event")
if synthesis[0].get("migrated_snapshot") is not True:
    raise SystemExit("migrated synthesis snapshot event is not marked")
if synthesis[0]["recorded_at"] != round_doc["synthesis_recorded_at"]:
    raise SystemExit("synthesis event did not preserve synthesis_recorded_at")
finalization = [item for item in events if item["event"] == "finalize"]
if len(finalization) != 1 or finalization[0]["event_id"] != "r01-round-finalize":
    raise SystemExit("terminal fixture is missing its deterministic finalization event")
if finalization[0]["recorded_at"] != round_doc["finalized_at"]:
    raise SystemExit("finalization event did not preserve finalized_at")
Path(sys.argv[3]).write_text(
    json.dumps(round_doc["synthesis"], indent=2) + "\n",
    encoding="utf-8",
)
PY
"$LEDGER" record-synthesis \
  --run-dir "$legacy_terminal_run" --round 1 --synthesis "$legacy_terminal_snapshot" >/dev/null
"$LEDGER" finalize-round \
  --run-dir "$legacy_terminal_run" --round 1 --decision stop \
  --summary "The recovery contract is covered." >/dev/null
[[ "$(event_count "$legacy_terminal_run/round-01.json" synthesis round)" == 1 ]] || \
  fail "base-format synthesis replay duplicated its normalized event"
[[ "$(event_count "$legacy_terminal_run/round-01.json" finalize round)" == 1 ]] || \
  fail "base-format finalization replay duplicated its normalized event"

case_name "base-format rounds normalize before status, continuation, and replay"
legacy_root="$tmpdir/legacy-root"
legacy_run="$(init_run "$legacy_root" "Legacy lifecycle fixture")"
"$LEDGER" prepare-round --run-dir "$legacy_run" --round 1 --assignments "$six" >/dev/null
"$LEDGER" record-spawn \
  --run-dir "$legacy_run" --round 1 --slot A1 --agent-id legacy-a1 --status spawned >/dev/null
python3 - "$legacy_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("updated_at", None)
round_doc["events"] = [
    {key: value for key, value in event.items() if key != "event_id"}
    for event in round_doc["events"]
    if event["event"] == "spawn"
]
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY

legacy_status="$($LEDGER status --run-dir "$legacy_run")"
python3 - "$legacy_status" "$legacy_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

status = json.loads(sys.argv[1])
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if status["status"] != "round_in_progress" or status["next_action"] != "continue_lifecycle":
    raise SystemExit("status did not reconcile the base-format lifecycle fixture")
events = round_doc["events"]
if [item["event_id"] for item in events] != ["r01-round-prepare", "r01-A1-spawn"]:
    raise SystemExit("base-format lifecycle events were not deterministically normalized")
if events[0]["recorded_at"] != round_doc["created_at"]:
    raise SystemExit("prepare event did not derive its base-format timestamp from created_at")
assignment = round_doc["assignments"][0]
if events[1]["recorded_at"] != assignment["spawn_recorded_at"]:
    raise SystemExit("spawn event did not preserve its base-format lifecycle timestamp")
PY
"$LEDGER" record-spawn \
  --run-dir "$legacy_run" --round 1 --slot A1 --agent-id legacy-a1 --status spawned >/dev/null
[[ "$(event_count "$legacy_run/round-01.json" spawn A1)" == 1 ]] || \
  fail "base-format spawn replay duplicated its normalized event"
"$LEDGER" record-result \
  --run-dir "$legacy_run" --round 1 --slot A1 --status completed --summary "Legacy A1 result" >/dev/null
"$LEDGER" record-result \
  --run-dir "$legacy_run" --round 1 --slot A1 --status completed --summary "Legacy A1 result" >/dev/null
[[ "$(event_count "$legacy_run/round-01.json" result A1)" == 1 ]] || \
  fail "legal continuation from a base-format round was not replay-safe"

legacy_empty_run="$(init_run "$legacy_root" "Legacy prepared fixture")"
"$LEDGER" prepare-round --run-dir "$legacy_empty_run" --round 1 --assignments "$six" >/dev/null
python3 - "$legacy_empty_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("events", None)
round_doc.pop("updated_at", None)
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
"$LEDGER" status --run-dir "$legacy_empty_run" >/dev/null
"$LEDGER" prepare-round \
  --run-dir "$legacy_empty_run" --round 1 --assignments "$six" >/dev/null
[[ "$(event_count "$legacy_empty_run/round-01.json" prepare round)" == 1 ]] || \
  fail "base-format prepare replay did not use one normalized prepare event"

case_name "migrated synthesis compatibility ends after a canonical correction"
legacy_correction_run="$(init_run \
  "$tmpdir/legacy-correction-root" "Legacy synthesis correction")"
"$LEDGER" prepare-round \
  --run-dir "$legacy_correction_run" --round 1 --assignments "$six" >/dev/null
for slot in A1 A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn \
    --run-dir "$legacy_correction_run" --round 1 --slot "$slot" \
    --agent-id "correction-$slot" --status spawned >/dev/null
  "$LEDGER" record-result \
    --run-dir "$legacy_correction_run" --round 1 --slot "$slot" \
    --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close \
    --run-dir "$legacy_correction_run" --round 1 --slot "$slot" --status closed >/dev/null
done
"$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 \
  --synthesis "$legacy_partial_synthesis" >/dev/null
python3 - "$legacy_correction_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
round_doc = json.loads(path.read_text(encoding="utf-8"))
round_doc.pop("updated_at", None)
round_doc["events"] = [
    {key: value for key, value in event.items() if key != "event_id"}
    for event in round_doc["events"]
    if event["event"] in {"spawn", "result", "close"}
]
path.write_text(json.dumps(round_doc, indent=2) + "\n", encoding="utf-8")
PY
"$LEDGER" status --run-dir "$legacy_correction_run" >/dev/null
migrated_snapshot="$tmpdir/migrated-snapshot.json"
python3 - "$legacy_correction_run/round-01.json" "$migrated_snapshot" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
synthesis_events = [item for item in round_doc["events"] if item["event"] == "synthesis"]
if len(synthesis_events) != 1 or synthesis_events[0].get("migrated_snapshot") is not True:
    raise SystemExit("normalization did not mark exactly one migrated synthesis snapshot")
Path(sys.argv[2]).write_text(
    json.dumps(round_doc["synthesis"], indent=2) + "\n",
    encoding="utf-8",
)
PY
"$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 --synthesis "$migrated_snapshot" >/dev/null
[[ "$(event_count "$legacy_correction_run/round-01.json" synthesis round)" == 1 ]] || \
  fail "exact migrated snapshot replay duplicated its event"

canonical_correction="$tmpdir/canonical-correction.json"
cat >"$canonical_correction" <<'JSON'
{"convergence": ["Recovery is deterministic."]}
JSON
"$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 --synthesis "$canonical_correction" >/dev/null
"$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 --synthesis "$canonical_correction" >/dev/null
python3 - "$legacy_correction_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
alignment = round_doc["synthesis"].get("objective_alignment")
if alignment is None or alignment.get("status") != "aligned":
    raise SystemExit("partial synthesis correction did not preserve canonical alignment")
PY
[[ "$(event_count "$legacy_correction_run/round-01.json" synthesis round)" == 2 ]] || \
  fail "canonical correction replay did not remain event-ID exact"

expect_failure_matching "canonical synthesis correction already exists" \
  "$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 --synthesis "$migrated_snapshot"

novel_matching_subset="$tmpdir/novel-matching-subset.json"
cat >"$novel_matching_subset" <<'JSON'
{"action_list": ["Keep round JSON canonical."]}
JSON
"$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 --synthesis "$novel_matching_subset" >/dev/null
"$LEDGER" record-synthesis \
  --run-dir "$legacy_correction_run" --round 1 --synthesis "$novel_matching_subset" >/dev/null
[[ "$(event_count "$legacy_correction_run/round-01.json" synthesis round)" == 3 ]] || \
  fail "second canonical correction or exact replay was not recorded normally"
python3 - "$legacy_correction_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
events = [item for item in round_doc["events"] if item["event"] == "synthesis"]
if len({item["event_id"] for item in events}) != 3:
    raise SystemExit("migrated snapshot and two canonical corrections need distinct event IDs")
if sum(item.get("migrated_snapshot") is True for item in events) != 1:
    raise SystemExit("only the migrated snapshot event may carry the compatibility marker")
PY

case_name "init interrupted before publish leaves no visible final run directory"
interrupted_root="$tmpdir/init-interrupted"
old_staging="$interrupted_root/.run-ledger-init-11111111-1111-4111-8111-111111111111"
recent_staging="$interrupted_root/.run-ledger-init-22222222-2222-4222-8222-222222222222"
unrelated_staging="$interrupted_root/.run-ledger-init-not-a-uuid"
mkdir -p "$old_staging" "$recent_staging" "$unrelated_staging"
touch -d '25 hours ago' "$old_staging" "$unrelated_staging"
expect_failpoint "init:after-state" \
  "$LEDGER" init \
  --root "$interrupted_root" \
  --mode review \
  --target docs/plan.md \
  --objective "Interrupt init before publication" \
  --spawn-tool spawn \
  --wait-tool wait \
  --close-tool close \
  --title "Interrupted init"
[[ ! -d "$old_staging" ]] || fail "init did not remove a stale UUID staging directory"
[[ -d "$recent_staging" ]] || fail "init removed a recent staging directory"
[[ -d "$unrelated_staging" ]] || fail "init removed a similarly named non-UUID directory"
if find "$interrupted_root" -mindepth 1 -maxdepth 1 -type d ! -name '.run-ledger-init-*' -print -quit | grep -q .; then
  fail "interrupted init exposed a final run directory"
fi

case_name "prepare-round interrupted after round JSON is repaired by status"
recovery_root="$tmpdir/recovery-root"
run_dir="$(init_run "$recovery_root" "Recovery cases")"
expect_failpoint "prepare-round:after-round-json" \
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 1 --assignments "$six"
[[ -f "$run_dir/round-01.json" ]] || fail "prepare failpoint did not publish canonical round JSON"
[[ ! -f "$run_dir/round-01.md" ]] || fail "prepare failpoint unexpectedly published round Markdown"
status_json="$($LEDGER status --run-dir "$run_dir")"
[[ -f "$run_dir/round-01.md" ]] || fail "status did not repair round Markdown"
python3 - "$status_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
if status["status"] != "round_in_progress":
    raise SystemExit("status did not derive round_in_progress from canonical round JSON")
if status["next_action"] != "continue_lifecycle":
    raise SystemExit("status did not derive continue_lifecycle for a planned round")
PY
"$LEDGER" prepare-round --run-dir "$run_dir" --round 1 --assignments "$six" >/dev/null
[[ "$(event_count "$run_dir/round-01.json" prepare round)" == 1 ]] || fail "prepare replay duplicated its event"
expect_failure "$LEDGER" prepare-round --run-dir "$run_dir" --round 1 --assignments "$different_six"

case_name "record-spawn exact replay returns success without a duplicate event"
"$LEDGER" record-spawn \
  --run-dir "$run_dir" --round 1 --slot A1 --agent-id agent-a1 --status spawned >/dev/null
"$LEDGER" record-spawn \
  --run-dir "$run_dir" --round 1 --slot A1 --agent-id agent-a1 --status spawned >/dev/null
[[ "$(event_count "$run_dir/round-01.json" spawn A1)" == 1 ]] || fail "spawn replay duplicated its event"
expect_failure "$LEDGER" record-spawn \
  --run-dir "$run_dir" --round 1 --slot A1 --agent-id other-agent --status spawned

case_name "record-result conflicting replay is rejected"
"$LEDGER" record-result \
  --run-dir "$run_dir" --round 1 --slot A1 --status completed --summary "A1 result" >/dev/null
"$LEDGER" record-result \
  --run-dir "$run_dir" --round 1 --slot A1 --status completed --summary "A1 result" >/dev/null
[[ "$(event_count "$run_dir/round-01.json" result A1)" == 1 ]] || fail "result replay duplicated its event"
expect_failure "$LEDGER" record-result \
  --run-dir "$run_dir" --round 1 --slot A1 --status completed --summary "Conflicting A1 result"

case_name "record-close interrupted before state projection is repaired"
expect_failpoint "record-close:after-round-markdown" \
  "$LEDGER" record-close --run-dir "$run_dir" --round 1 --slot A1 --status closed
python3 - "$run_dir/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignment = next(item for item in round_doc["assignments"] if item["slot"] == "A1")
if assignment["close_status"] != "closed":
    raise SystemExit("close failpoint did not commit canonical round JSON")
PY
"$LEDGER" status --run-dir "$run_dir" >/dev/null
"$LEDGER" record-close --run-dir "$run_dir" --round 1 --slot A1 --status closed >/dev/null
[[ "$(event_count "$run_dir/round-01.json" close A1)" == 1 ]] || fail "close replay duplicated its event"
expect_failure "$LEDGER" record-close --run-dir "$run_dir" --round 1 --slot A1 --status failed

for slot in A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn \
    --run-dir "$run_dir" --round 1 --slot "$slot" --agent-id "agent-${slot,,}" --status spawned >/dev/null
  "$LEDGER" record-result \
    --run-dir "$run_dir" --round 1 --slot "$slot" --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close \
    --run-dir "$run_dir" --round 1 --slot "$slot" --status closed >/dev/null
done

case_name "record-synthesis interrupted before ledger projection is repaired"
expect_failpoint "record-synthesis:after-state" \
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$synthesis"
synthesis_event_id="$(python3 - "$run_dir/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(next(item["event_id"] for item in round_doc["events"] if item["event"] == "synthesis"))
PY
)"
if grep -q "$synthesis_event_id" "$run_dir/ledger.md"; then
  fail "synthesis failpoint unexpectedly published the ledger projection"
fi
"$LEDGER" status --run-dir "$run_dir" >/dev/null
grep -q "$synthesis_event_id" "$run_dir/ledger.md" || fail "status did not repair the ledger projection"
"$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$synthesis" >/dev/null
[[ "$(event_count "$run_dir/round-01.json" synthesis round)" == 1 ]] || fail "synthesis replay duplicated its event"
"$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$corrected_synthesis" >/dev/null
"$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$corrected_synthesis" >/dev/null
[[ "$(event_count "$run_dir/round-01.json" synthesis round)" == 2 ]] || fail "synthesis correction or replay was not canonical"

case_name "finalize-round interrupted after terminal round JSON derives terminal state"
expect_failpoint "finalize-round:after-round-json" \
  "$LEDGER" finalize-round \
  --run-dir "$run_dir" --round 1 --decision stop --summary "Recovery is complete"
status_json="$($LEDGER status --run-dir "$run_dir")"
python3 - "$status_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
if status["status"] != "complete" or status["next_action"] != "complete":
    raise SystemExit("status did not derive terminal run state from finalized round JSON")
if status["last_finalized_round"] != 1:
    raise SystemExit("status did not derive last_finalized_round")
PY
"$LEDGER" finalize-round \
  --run-dir "$run_dir" --round 1 --decision stop --summary "Recovery is complete" >/dev/null
[[ "$(event_count "$run_dir/round-01.json" finalize round)" == 1 ]] || fail "finalize replay duplicated its event"
expect_failure "$LEDGER" finalize-round \
  --run-dir "$run_dir" --round 1 --decision stop --summary "Conflicting final summary"

case_name "two concurrent mutating commands preserve both legal updates"
concurrent_run="$(init_run "$tmpdir/concurrent-root" "Concurrent mutations")"
"$LEDGER" prepare-round --run-dir "$concurrent_run" --round 1 --assignments "$six" >/dev/null
"$LEDGER" record-spawn \
  --run-dir "$concurrent_run" --round 1 --slot A1 --agent-id concurrent-a1 --status spawned >/dev/null &
first_pid=$!
"$LEDGER" record-spawn \
  --run-dir "$concurrent_run" --round 1 --slot A2 --agent-id concurrent-a2 --status spawned >/dev/null &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
python3 - "$concurrent_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments = {item["slot"]: item for item in round_doc["assignments"]}
for slot in ("A1", "A2"):
    if assignments[slot]["spawn_status"] != "spawned":
        raise SystemExit(f"concurrent update for {slot} was lost")
events = [item for item in round_doc["events"] if item["event"] == "spawn"]
if {item["slot"] for item in events} != {"A1", "A2"}:
    raise SystemExit("concurrent spawn events were not both preserved")
PY

case_name "status waits for an active writer and returns one consistent snapshot"
lock_ready="$tmpdir/lock-ready"
lock_release="$tmpdir/lock-release"
python3 - "$concurrent_run/.run-ledger.lock" "$lock_ready" "$lock_release" <<'PY' &
import fcntl
import sys
import time
from pathlib import Path

with Path(sys.argv[1]).open("a+", encoding="utf-8") as handle:
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    Path(sys.argv[2]).write_text("ready\n", encoding="utf-8")
    deadline = time.monotonic() + 10
    while not Path(sys.argv[3]).exists():
        if time.monotonic() > deadline:
            raise SystemExit("timed out waiting to release test lock")
        time.sleep(0.01)
PY
lock_pid=$!
for _ in $(seq 1 100); do
  [[ -f "$lock_ready" ]] && break
  sleep 0.01
done
[[ -f "$lock_ready" ]] || fail "lock holder did not start"
"$LEDGER" status --run-dir "$concurrent_run" >"$tmpdir/waited-status.json" &
status_pid=$!
sleep 0.2
kill -0 "$status_pid" 2>/dev/null || fail "status returned before the active writer released the lock"
touch "$lock_release"
wait "$lock_pid"
wait "$status_pid"
python3 - "$tmpdir/waited-status.json" "$concurrent_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

status = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
spawned = sum(1 for item in round_doc["assignments"] if item["spawn_status"] == "spawned")
if status["rounds"]["round-01"]["spawned"] != spawned:
    raise SystemExit("status returned a snapshot inconsistent with canonical round JSON")
PY

case_name "every repaired JSON file parses successfully"
python3 - "$recovery_root" "$tmpdir/concurrent-root" <<'PY'
import json
import sys
from pathlib import Path

for root_name in sys.argv[1:]:
    for path in Path(root_name).glob("*/state.json"):
        json.loads(path.read_text(encoding="utf-8"))
    for path in Path(root_name).glob("*/round-[0-9][0-9].json"):
        json.loads(path.read_text(encoding="utf-8"))
PY

case_name "repaired round Markdown matches rendering from round JSON"
printf 'stale projection\n' >"$run_dir/round-01.md"
"$LEDGER" status --run-dir "$run_dir" >/dev/null
python3 - "$LEDGER" "$run_dir/round-01.json" "$run_dir/round-01.md" <<'PY'
import json
import runpy
import sys
from pathlib import Path

module = runpy.run_path(sys.argv[1])
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
actual = Path(sys.argv[3]).read_text(encoding="utf-8")
expected = module["render_round_markdown"](round_doc)
if actual != expected:
    raise SystemExit("repaired round Markdown does not match canonical rendering")
PY

case_name "repaired ledger contains one logical event per canonical round event"
printf 'stale projection\n' >"$run_dir/ledger.md"
"$LEDGER" status --run-dir "$run_dir" >/dev/null
python3 - "$run_dir" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

run_dir = Path(sys.argv[1])
canonical_ids = []
for path in sorted(run_dir.glob("round-[0-9][0-9].json")):
    round_doc = json.loads(path.read_text(encoding="utf-8"))
    canonical_ids.extend(item["event_id"] for item in round_doc.get("events", []))
ledger_ids = [
    line.split(" | ", 2)[1]
    for line in (run_dir / "ledger.md").read_text(encoding="utf-8").splitlines()
    if " | " in line
]
if Counter(ledger_ids) != Counter(canonical_ids):
    raise SystemExit("ledger projection does not contain one line per canonical event")
if len(ledger_ids) != len(set(ledger_ids)):
    raise SystemExit("ledger projection contains duplicate logical events")
PY

echo "run-ledger deterministic recovery looks good"
