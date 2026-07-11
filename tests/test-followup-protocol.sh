#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="$REPO_ROOT/scripts/run-ledger"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

six="$tmpdir/six.json"
cat >"$six" <<'JSON'
[
  {"slot":"B1","lens":"Goal And Requirement Alignment","question":"What objective, requirements, and constraints must this satisfy?"},
  {"slot":"B2","lens":"Mechanism And Structural Validity","question":"What causal mechanism and structural boundaries make this viable?"},
  {"slot":"B3","lens":"Evidence And Uncertainty Audit","question":"What evidence, assumptions, and falsification conditions matter?"},
  {"slot":"B4","lens":"Alternatives And Decision Value","question":"Which alternatives, costs, and reversibility tradeoffs change the decision?"},
  {"slot":"B5","lens":"Risk And Robustness","question":"Which hostile conditions, failures, and recovery paths matter?"},
  {"slot":"B6","lens":"Execution And Lifecycle","question":"What delivery, testing, operations, and ownership work is required?"}
]
JSON

legacy_six="$tmpdir/legacy-six.json"
cat >"$legacy_six" <<'JSON'
[
  {"slot":"A1","lens":"First Principles","question":"What assumptions must hold?"},
  {"slot":"A2","lens":"Occam's Razor","question":"What can be simplified?"},
  {"slot":"A3","lens":"Bounded Bayesian","question":"What changes confidence?"},
  {"slot":"A4","lens":"Expected Cost Optimality","question":"What is the cost of error?"},
  {"slot":"A5","lens":"Adversarial Review","question":"How can this fail?"},
  {"slot":"A6","lens":"Execution Friction","question":"What impedes execution?"}
]
JSON

fail() {
  echo "$*" >&2
  exit 1
}

assert_rejected() {
  local message="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$message"
  fi
}

assert_plan_replay_unchanged() {
  local run_dir="$1"
  local round="$2"
  local slot="$3"
  local round_json="$run_dir/round-$(printf '%02d' "$round").json"
  local before
  local after
  before="$(sha256sum "$round_json")"
  "$LEDGER" plan-dispatch --run-dir "$run_dir" --round "$round" --slot "$slot" >/dev/null
  after="$(sha256sum "$round_json")"
  [[ "$before" == "$after" ]] || fail "exact plan replay mutated $round_json for $slot"
}

init_run() {
  local name="$1"
  "$LEDGER" init \
    --root "$tmpdir/$name" \
    --mode review \
    --target plan.md \
    --objective "Exercise adaptive follow-up protocol" \
    --spawn-tool spawn \
    --wait-tool wait \
    --close-tool close \
    --title "$name"
}

complete_round() {
  local run_dir="$1"
  local round="$2"
  local slots
  slots="$(python3 - "$run_dir/round-$(printf '%02d' "$round").json" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(" ".join(item["slot"] for item in doc["assignments"]))
PY
)"
  for slot in $slots; do
    "$LEDGER" plan-dispatch --run-dir "$run_dir" --round "$round" --slot "$slot" >/dev/null
    "$LEDGER" record-spawn --run-dir "$run_dir" --round "$round" --slot "$slot" \
      --status spawned --agent-id "agent-r${round}-${slot}" >/dev/null
    "$LEDGER" record-result --run-dir "$run_dir" --round "$round" --slot "$slot" \
      --status completed --summary "$slot result" >/dev/null
    "$LEDGER" record-close --run-dir "$run_dir" --round "$round" --slot "$slot" \
      --status closed >/dev/null
  done
}

write_targets() {
  local path="$1"
  local singles="$2"
  local duals="$3"
  local prefix="${4:-t}"
  python3 - "$path" "$singles" "$duals" "$prefix" <<'PY'
import json
import sys
from pathlib import Path

path, singles, duals, prefix = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
targets = []
for index in range(1, singles + 1):
    targets.append({
        "target_id": f"{prefix}{index}",
        "source_slot": "B1",
        "claim": f"Claim {prefix}{index}",
        "why_decision_critical": f"Why {prefix}{index} changes the decision",
        "review_policy": "single",
        "conflict_ref": None,
        "disposition": "pending",
    })
for index in range(1, duals + 1):
    target_id = f"{prefix}{singles + index}"
    targets.append({
        "target_id": target_id,
        "source_slot": "B2",
        "claim": f"Claim {target_id}",
        "why_decision_critical": f"Why {target_id} changes the decision",
        "review_policy": "dual",
        "conflict_ref": "critical_disagreements[0]",
        "disposition": "pending",
    })
path.write_text(json.dumps(targets, indent=2) + "\n", encoding="utf-8")
PY
}

write_synthesis() {
  local path="$1"
  local targets_path="$2"
  local outcomes_path="$3"
  python3 - "$path" "$targets_path" "$outcomes_path" <<'PY'
import json
import sys
from pathlib import Path

path, targets_path, outcomes_path = map(Path, sys.argv[1:])
targets = json.loads(targets_path.read_text(encoding="utf-8")) if targets_path.exists() else []
outcomes = json.loads(outcomes_path.read_text(encoding="utf-8")) if outcomes_path.exists() else []
payload = {
    "convergence": ["The completed workers produced usable evidence."],
    "disagreement": [],
    "critical_disagreements": ["A decision-critical conflict remains."]
        if any(item["review_policy"] == "dual" for item in targets) else [],
    "cannot_verify": [],
    "high_impact_low_evidence": [],
    "action_list": ["Apply the derived follow-up decision."],
    "cross_review_targets": targets,
    "cross_review_outcomes": outcomes,
    "expected_value_of_another_round": "Derived from the canonical backlog.",
    "objective_alignment": {
        "status": "aligned",
        "rationale": "This protocol fixture isolates canonical backlog behavior from objective-quality judgment.",
        "unmet_requirements": [],
    },
    "stop_reason": "",
    "next_round_question": "",
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_needs_revision_synthesis() {
  local path="$1"
  local targets_path="$2"
  local outcomes_path="$3"
  local rationale="$4"
  local unmet_requirement="$5"
  write_synthesis "$path" "$targets_path" "$outcomes_path"
  python3 - "$path" "$rationale" "$unmet_requirement" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["objective_alignment"] = {
    "status": "needs_revision",
    "rationale": sys.argv[2],
    "unmet_requirements": [sys.argv[3]],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_outcomes() {
  local path="$1"
  shift
  python3 - "$path" "$@" <<'PY'
import json
import sys
from pathlib import Path

outcomes = []
for value in sys.argv[2:]:
    target_id, status = value.split("=", 1)
    outcomes.append({"target_id": target_id, "status": status, "rationale": f"{target_id} is {status}."})
Path(sys.argv[1]).write_text(json.dumps(outcomes, indent=2) + "\n", encoding="utf-8")
PY
}

write_assignments() {
  local path="$1"
  shift
  python3 - "$path" "$@" <<'PY'
import json
import sys
from pathlib import Path

items = []
for index, target_id in enumerate(sys.argv[2:], start=1):
    items.append({
        "slot": f"C{index}",
        "lens": f"Follow-up lens {index}",
        "question": f"Resolve {target_id}",
        "target_id": target_id,
    })
Path(sys.argv[1]).write_text(json.dumps(items, indent=2) + "\n", encoding="utf-8")
PY
}

record_round_one_targets() {
  local run_dir="$1"
  local targets_path="$2"
  local synthesis="$tmpdir/synthesis-$(basename "$run_dir")-r1.json"
  local empty="$tmpdir/empty-outcomes.json"
  printf '[]\n' >"$empty"
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 1 --assignments "$six" >/dev/null
  complete_round "$run_dir" 1
  write_synthesis "$synthesis" "$targets_path" "$empty"
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$synthesis" >/dev/null
  "$LEDGER" finalize-round --run-dir "$run_dir" --round 1 --decision continue_round_2 \
    --summary "Review the pending canonical backlog." >/dev/null
}

make_pending_run() {
  local name="$1"
  local singles="$2"
  local duals="$3"
  local targets="$tmpdir/$name-targets.json"
  local run_dir
  run_dir="$(init_run "$name")"
  write_targets "$targets" "$singles" "$duals"
  record_round_one_targets "$run_dir" "$targets"
  printf '%s\n' "$run_dir"
}

assert_round_batch() {
  local run_dir="$1"
  local round="$2"
  local expected_agents="$3"
  local expected_incoming="$4"
  local expected_active="$5"
  python3 - "$run_dir/round-$(printf '%02d' "$round").json" \
    "$expected_agents" "$expected_incoming" "$expected_active" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_agents = int(sys.argv[2])
incoming = sys.argv[3].split(",") if sys.argv[3] else []
active = sys.argv[4].split(",") if sys.argv[4] else []
if doc.get("expected_agents") != expected_agents:
    raise SystemExit(f"expected_agents mismatch: {doc.get('expected_agents')}")
if doc.get("incoming_backlog_ids") != incoming:
    raise SystemExit(f"incoming backlog mismatch: {doc.get('incoming_backlog_ids')}")
if doc.get("active_target_ids") != active:
    raise SystemExit(f"active targets mismatch: {doc.get('active_target_ids')}")
slots = [item["slot"] for item in doc["assignments"]]
if slots != [f"C{i}" for i in range(1, expected_agents + 1)]:
    raise SystemExit(f"non-consecutive C slots: {slots}")
PY
}

review_quota_case() {
  python3 - "$LEDGER" "$tmpdir/reviewer-quota" <<'PY'
import json
import runpy
import sys
from pathlib import Path

module = runpy.run_path(sys.argv[1])
root = Path(sys.argv[2])


def build_case(name, policy, review_counts):
    run_dir = root / name
    run_dir.mkdir(parents=True)
    target = {
        "target_id": "t1",
        "source_slot": "A1",
        "claim": "Quota claim",
        "why_decision_critical": "Quota changes review scope",
        "review_policy": policy,
        "conflict_ref": None if policy == "single" else "critical_disagreements[0]",
        "disposition": "pending",
    }
    (run_dir / "round-01.json").write_text(
        json.dumps({"round": 1, "synthesis": {"cross_review_targets": [target]}}) + "\n",
        encoding="utf-8",
    )
    for round_number, count in enumerate(review_counts, start=2):
        assignments = [
            {"slot": f"C{index}", "target_id": "t1", "result_status": "completed"}
            for index in range(1, count + 1)
        ]
        (run_dir / f"round-{round_number:02d}.json").write_text(
            json.dumps(
                {
                    "round": round_number,
                    "assignments": assignments,
                    "synthesis": {
                        "cross_review_targets": [],
                        "cross_review_outcomes": [
                            {"target_id": "t1", "status": "unresolved", "rationale": "Still open"}
                        ],
                    },
                }
            )
            + "\n",
            encoding="utf-8",
        )
    return run_dir


cases = [
    ("single-initial", "single", [], 1),
    ("single-tie", "single", [1], 1),
    ("single-exhausted", "single", [1, 1], 0),
    ("dual-initial", "dual", [], 2),
    ("dual-tie", "dual", [2], 1),
    ("dual-exhausted", "dual", [2, 1], 0),
]
for name, policy, counts, expected in cases:
    actual = module["seats_required"](build_case(name, policy, counts), "t1")
    if actual != expected:
        raise SystemExit(f"{name} expected {expected} remaining seats, got {actual}")
PY
}

review_exhausted_case() {
  local run_dir
  run_dir="$(make_pending_run review-exhausted 0 1)"
  write_assignments "$tmpdir/review-exhausted-r2.json" t1 t1
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 2 \
    --assignments "$tmpdir/review-exhausted-r2.json" >/dev/null
  complete_round "$run_dir" 2
  write_outcomes "$tmpdir/review-exhausted-unresolved.json" t1=unresolved
  write_synthesis "$tmpdir/review-exhausted-synthesis-r2.json" \
    "$tmpdir/no-review-exhausted-targets.json" "$tmpdir/review-exhausted-unresolved.json"
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 2 \
    --synthesis "$tmpdir/review-exhausted-synthesis-r2.json" >/dev/null
  "$LEDGER" finalize-round --run-dir "$run_dir" --round 2 --decision ask_user \
    --summary "Authorize the only tie-break." >/dev/null

  write_assignments "$tmpdir/review-exhausted-r3.json" t1
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 3 \
    --assignments "$tmpdir/review-exhausted-r3.json" --user-approved >/dev/null
  complete_round "$run_dir" 3
  write_synthesis "$tmpdir/review-exhausted-synthesis-r3.json" \
    "$tmpdir/no-review-exhausted-targets.json" "$tmpdir/review-exhausted-unresolved.json"
  assert_rejected "exhausted unresolved synthesis must be rejected before commit" \
    "$LEDGER" record-synthesis --run-dir "$run_dir" --round 3 \
    --synthesis "$tmpdir/review-exhausted-synthesis-r3.json"
  assert_rejected "exhausted unresolved round must not finalize after rejected synthesis" \
    "$LEDGER" finalize-round --run-dir "$run_dir" --round 3 --decision ask_user \
    --summary "Do not finalize an exhausted unresolved target."
}

review_prepare_replay_case() {
  local run_dir
  run_dir="$(make_pending_run review-prepare-replay 1 0)"
  write_assignments "$tmpdir/review-prepare-replay-r2.json" t1
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 2 \
    --assignments "$tmpdir/review-prepare-replay-r2.json" >/dev/null
  complete_round "$run_dir" 2
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 2 \
    --assignments "$tmpdir/review-prepare-replay-r2.json" >/dev/null

  write_outcomes "$tmpdir/review-prepare-replay-outcome.json" t1=accepted
  write_synthesis "$tmpdir/review-prepare-replay-synthesis.json" \
    "$tmpdir/no-review-prepare-targets.json" "$tmpdir/review-prepare-replay-outcome.json"
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 2 \
    --synthesis "$tmpdir/review-prepare-replay-synthesis.json" >/dev/null
  "$LEDGER" finalize-round --run-dir "$run_dir" --round 2 --decision stop \
    --summary "Replay remains authoritative after finalization." >/dev/null
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 2 \
    --assignments "$tmpdir/review-prepare-replay-r2.json" >/dev/null
}

review_plan_replay_case() {
  local run_dir
  run_dir="$(init_run review-plan-replay)"
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 1 --assignments "$six" >/dev/null

  "$LEDGER" plan-dispatch --run-dir "$run_dir" --round 1 --slot B1 >/dev/null
  "$LEDGER" record-spawn --run-dir "$run_dir" --round 1 --slot B1 --status unknown >/dev/null
  assert_plan_replay_unchanged "$run_dir" 1 B1
  assert_rejected "unknown dispatch must remain terminal after exact plan replay" \
    "$LEDGER" record-spawn --run-dir "$run_dir" --round 1 --slot B1 \
    --status spawned --agent-id replacement-a1

  "$LEDGER" plan-dispatch --run-dir "$run_dir" --round 1 --slot B2 >/dev/null
  "$LEDGER" record-spawn --run-dir "$run_dir" --round 1 --slot B2 \
    --status spawned --agent-id agent-a2 >/dev/null
  assert_plan_replay_unchanged "$run_dir" 1 B2
  "$LEDGER" record-result --run-dir "$run_dir" --round 1 --slot B2 \
    --status completed --summary "Known worker drained." >/dev/null
  "$LEDGER" record-close --run-dir "$run_dir" --round 1 --slot B2 --status closed >/dev/null

  "$LEDGER" plan-dispatch --run-dir "$run_dir" --round 1 --slot B3 >/dev/null
  "$LEDGER" record-spawn --run-dir "$run_dir" --round 1 --slot B3 --status failed >/dev/null
  assert_plan_replay_unchanged "$run_dir" 1 B3

  "$LEDGER" finalize-round --run-dir "$run_dir" --round 1 --decision stop \
    --summary "Unknown and failed dispatches block the round." --blocked >/dev/null
  assert_plan_replay_unchanged "$run_dir" 1 B1
  assert_plan_replay_unchanged "$run_dir" 1 B2
  assert_plan_replay_unchanged "$run_dir" 1 B3
}

adaptive_dispatch_provenance_case() {
  local round_one_run
  round_one_run="$(init_run adaptive-dispatch-provenance-round-one)"
  "$LEDGER" prepare-round --run-dir "$round_one_run" --round 1 --assignments "$six" >/dev/null
  assert_rejected "adaptive Round 1 spawned dispatch must be planned first" \
    "$LEDGER" record-spawn --run-dir "$round_one_run" --round 1 --slot B1 \
    --status spawned --agent-id planned-agent
  assert_rejected "adaptive Round 1 unknown dispatch must be planned first" \
    "$LEDGER" record-spawn --run-dir "$round_one_run" --round 1 --slot B2 --status unknown
  assert_rejected "adaptive Round 1 failed dispatch must be planned first" \
    "$LEDGER" record-spawn --run-dir "$round_one_run" --round 1 --slot B3 --status failed

  "$LEDGER" plan-dispatch --run-dir "$round_one_run" --round 1 --slot B1 >/dev/null
  "$LEDGER" record-spawn --run-dir "$round_one_run" --round 1 --slot B1 \
    --status spawned --agent-id unique-agent >/dev/null
  "$LEDGER" record-spawn --run-dir "$round_one_run" --round 1 --slot B1 \
    --status spawned --agent-id unique-agent >/dev/null
  "$LEDGER" plan-dispatch --run-dir "$round_one_run" --round 1 --slot B2 >/dev/null
  assert_rejected "spawned agent ids must be unique across adaptive slots" \
    "$LEDGER" record-spawn --run-dir "$round_one_run" --round 1 --slot B2 \
    --status spawned --agent-id unique-agent

  local followup_run
  followup_run="$(make_pending_run adaptive-dispatch-provenance-followup 1 0)"
  write_assignments "$tmpdir/adaptive-dispatch-provenance-r2.json" t1
  "$LEDGER" prepare-round --run-dir "$followup_run" --round 2 \
    --assignments "$tmpdir/adaptive-dispatch-provenance-r2.json" >/dev/null
  assert_rejected "adaptive follow-up unknown dispatch must be planned first" \
    "$LEDGER" record-spawn --run-dir "$followup_run" --round 2 --slot C1 --status unknown
  assert_rejected "adaptive follow-up failed dispatch must be planned first" \
    "$LEDGER" record-spawn --run-dir "$followup_run" --round 2 --slot C1 --status failed
  assert_rejected "adaptive follow-up spawned dispatch must be planned first" \
    "$LEDGER" record-spawn --run-dir "$followup_run" --round 2 --slot C1 \
    --status spawned --agent-id agent-r2-C1
  "$LEDGER" plan-dispatch --run-dir "$followup_run" --round 2 --slot C1 >/dev/null
  assert_rejected "spawned agent ids must be unique across adaptive rounds" \
    "$LEDGER" record-spawn --run-dir "$followup_run" --round 2 --slot C1 \
    --status spawned --agent-id agent-r1-B1
  "$LEDGER" record-spawn --run-dir "$followup_run" --round 2 --slot C1 \
    --status spawned --agent-id agent-r2-C1 >/dev/null
}

adaptive_lossless_correction_case() {
  local run_dir
  local initial_targets="$tmpdir/lossless-initial-targets.json"
  local empty="$tmpdir/lossless-empty.json"
  local erased="$tmpdir/lossless-erased-synthesis.json"
  local appended_targets="$tmpdir/lossless-appended-targets.json"
  local appended="$tmpdir/lossless-appended-synthesis.json"
  run_dir="$(init_run adaptive-lossless-correction)"
  printf '[]\n' >"$empty"
  write_targets "$initial_targets" 1 0
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 1 --assignments "$six" >/dev/null
  complete_round "$run_dir" 1
  write_synthesis "$tmpdir/lossless-initial-synthesis.json" "$initial_targets" "$empty"
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 \
    --synthesis "$tmpdir/lossless-initial-synthesis.json" >/dev/null

  write_synthesis "$erased" "$empty" "$empty"
  assert_rejected "a correction cannot erase canonical cross-review targets" \
    "$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$erased"
  assert_rejected "an erased correction cannot derive an adaptive stop" \
    "$LEDGER" finalize-round --run-dir "$run_dir" --round 1 --decision stop \
    --summary "The pending target remains canonical."

  python3 - "$initial_targets" "$appended_targets" <<'PY'
import json
import sys
from pathlib import Path

targets = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
targets.append({
    "target_id": "t2",
    "source_slot": "B2",
    "claim": "Claim t2",
    "why_decision_critical": "Why t2 changes the decision",
    "review_policy": "single",
    "conflict_ref": None,
    "disposition": "pending",
})
Path(sys.argv[2]).write_text(json.dumps(targets, indent=2) + "\n", encoding="utf-8")
PY
  write_synthesis "$appended" "$appended_targets" "$empty"
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 1 --synthesis "$appended" >/dev/null
  python3 - "$run_dir/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

targets = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["synthesis"]["cross_review_targets"]
if [item["target_id"] for item in targets] != ["t1", "t2"]:
    raise SystemExit("lossless correction did not retain the canonical target prefix")
PY
}

adaptive_followup_correction_limit_case() {
  local run_dir
  local round_one_targets="$tmpdir/followup-correction-round-one-targets.json"
  local initial_targets="$tmpdir/followup-correction-initial-targets.json"
  local appended_targets="$tmpdir/followup-correction-appended-targets.json"
  local outcomes="$tmpdir/followup-correction-outcomes.json"
  local empty="$tmpdir/followup-correction-empty.json"
  run_dir="$(init_run adaptive-followup-correction-limit)"
  printf '[]\n' >"$empty"
  write_targets "$round_one_targets" 1 0
  record_round_one_targets "$run_dir" "$round_one_targets"
  write_assignments "$tmpdir/followup-correction-r2-assignments.json" t1
  "$LEDGER" prepare-round --run-dir "$run_dir" --round 2 \
    --assignments "$tmpdir/followup-correction-r2-assignments.json" >/dev/null
  complete_round "$run_dir" 2
  write_outcomes "$outcomes" t1=accepted
  python3 - "$initial_targets" "$appended_targets" <<'PY'
import json
import sys
from pathlib import Path

target = {
    "target_id": "tX",
    "source_slot": "C1",
    "claim": "Fresh Round 2 claim",
    "why_decision_critical": "The fresh claim changes the decision.",
    "review_policy": "single",
    "conflict_ref": None,
    "disposition": "pending",
}
Path(sys.argv[1]).write_text(json.dumps([target], indent=2) + "\n", encoding="utf-8")
appended = {**target, "target_id": "tY", "claim": "Second fresh Round 2 claim"}
Path(sys.argv[2]).write_text(json.dumps([target, appended], indent=2) + "\n", encoding="utf-8")
PY
  write_synthesis "$tmpdir/followup-correction-initial-synthesis.json" "$initial_targets" "$outcomes"
  "$LEDGER" record-synthesis --run-dir "$run_dir" --round 2 \
    --synthesis "$tmpdir/followup-correction-initial-synthesis.json" >/dev/null
  write_synthesis "$tmpdir/followup-correction-appended-synthesis.json" "$appended_targets" "$outcomes"
  assert_rejected "a follow-up correction cannot introduce a second canonical target" \
    "$LEDGER" record-synthesis --run-dir "$run_dir" --round 2 \
    --synthesis "$tmpdir/followup-correction-appended-synthesis.json"
  python3 - "$run_dir/round-02.json" <<'PY'
import json
import sys
from pathlib import Path

targets = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["synthesis"]["cross_review_targets"]
if [item["target_id"] for item in targets] != ["tX"]:
    raise SystemExit("rejected follow-up correction mutated canonical targets")
PY
}

adaptive_needs_revision_stop_case() {
  local round_one_run
  local round_two_run
  local no_targets="$tmpdir/needs-revision-no-targets.json"
  local one_target="$tmpdir/needs-revision-one-target.json"
  printf '[]\n' >"$no_targets"

  round_one_run="$(init_run adaptive-needs-revision-stop-round-one)"
  "$LEDGER" prepare-round --run-dir "$round_one_run" --round 1 --assignments "$six" >/dev/null
  complete_round "$round_one_run" 1
  write_needs_revision_synthesis "$tmpdir/needs-revision-stop-r1.json" "$no_targets" "$no_targets" \
    "The review identifies a requirement the target still does not meet." \
    "Revise the target before relying on it."
  "$LEDGER" record-synthesis --run-dir "$round_one_run" --round 1 \
    --synthesis "$tmpdir/needs-revision-stop-r1.json" >/dev/null
  "$LEDGER" finalize-round --run-dir "$round_one_run" --round 1 --decision stop \
    --summary "No cross-review uncertainty remains; the needs-revision finding stands." >/dev/null

  round_two_run="$(init_run adaptive-needs-revision-stop-round-two)"
  write_targets "$one_target" 1 0
  record_round_one_targets "$round_two_run" "$one_target"
  write_assignments "$tmpdir/needs-revision-stop-r2-assignments.json" t1
  "$LEDGER" prepare-round --run-dir "$round_two_run" --round 2 \
    --assignments "$tmpdir/needs-revision-stop-r2-assignments.json" >/dev/null
  complete_round "$round_two_run" 2
  write_outcomes "$tmpdir/needs-revision-stop-r2-outcomes.json" t1=accepted
  write_needs_revision_synthesis "$tmpdir/needs-revision-stop-r2.json" "$no_targets" \
    "$tmpdir/needs-revision-stop-r2-outcomes.json" \
    "The cross-review uncertainty is resolved, but the target still needs revision." \
    "Revise the target before using the recommendation."
  "$LEDGER" record-synthesis --run-dir "$round_two_run" --round 2 \
    --synthesis "$tmpdir/needs-revision-stop-r2.json" >/dev/null
  "$LEDGER" finalize-round --run-dir "$round_two_run" --round 2 --decision stop \
    --summary "The backlog is empty; needs_revision remains the review finding." >/dev/null
}

case "${TASK2_REVIEW_CASE:-all}" in
  quota) review_quota_case; exit 0 ;;
  exhausted) review_exhausted_case; exit 0 ;;
  prepare-replay) review_prepare_replay_case; exit 0 ;;
  plan-replay) review_plan_replay_case; exit 0 ;;
  provenance) adaptive_dispatch_provenance_case; exit 0 ;;
  corrections) adaptive_lossless_correction_case; exit 0 ;;
  followup-correction-limit) adaptive_followup_correction_limit_case; exit 0 ;;
  needs-revision-stop) adaptive_needs_revision_stop_case; exit 0 ;;
  all)
    review_quota_case
    review_exhausted_case
    review_prepare_replay_case
    review_plan_replay_case
    adaptive_dispatch_provenance_case
    adaptive_lossless_correction_case
    adaptive_followup_correction_limit_case
    adaptive_needs_revision_stop_case
    ;;
  *) fail "unknown TASK2_REVIEW_CASE=${TASK2_REVIEW_CASE}" ;;
esac

# New runs opt in, while missing protocol_version remains strict legacy behavior.
protocol_run="$(init_run protocol-version)"
python3 - "$protocol_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if state.get("protocol_version") != "adaptive-backlog-v1":
    raise SystemExit("new init must store adaptive-backlog-v1")
PY

python3 - "$LEDGER" "$tmpdir/unbounded-round-files" <<'PY'
import json
import runpy
import sys
from pathlib import Path

module = runpy.run_path(sys.argv[1])
run_dir = Path(sys.argv[2])
run_dir.mkdir()
for number in (99, 100):
    (run_dir / f"round-{number:02d}.json").write_text(
        json.dumps({"round": number}) + "\n",
        encoding="utf-8",
    )
rounds = module["load_all_rounds"](run_dir)
if [item["round"] for item in rounds] != [99, 100]:
    raise SystemExit("adaptive round discovery must remain numeric beyond two digits")
PY

legacy_run="$(init_run legacy-compatibility)"
python3 - "$legacy_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state.pop("protocol_version", None)
state.pop("review_portfolio_version", None)
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
"$LEDGER" prepare-round --run-dir "$legacy_run" --round 1 --assignments "$legacy_six" >/dev/null
complete_round "$legacy_run" 1
legacy_synthesis="$tmpdir/legacy-synthesis.json"
cat >"$legacy_synthesis" <<'JSON'
{
  "convergence":["Legacy evidence converged."],
  "disagreement":[],
  "critical_disagreements":["Legacy disagreement."],
  "cannot_verify":[],
  "high_impact_low_evidence":[],
  "action_list":["Run legacy Round 2."],
  "cross_review_gate_status":"needs_cross_review",
  "cross_review_targets":[{"target_id":"legacy-t","source_slot":"A1","claim":"Legacy claim","why_decision_critical":"Legacy reason","disposition":"pending"}],
  "cross_review_outcomes":[],
  "expected_value_of_another_round":"Legacy fixed-six follow-up is required.",
  "objective_alignment":{
    "status":"aligned",
    "rationale":"This protocol fixture isolates legacy follow-up behavior from objective-quality judgment.",
    "unmet_requirements":[]
  },
  "next_round_decision":"continue_round_2",
  "stop_reason":"",
  "next_round_question":"Review legacy-t."
}
JSON
"$LEDGER" record-synthesis --run-dir "$legacy_run" --round 1 --synthesis "$legacy_synthesis" >/dev/null
"$LEDGER" finalize-round --run-dir "$legacy_run" --round 1 --decision continue_round_2 \
  --summary "Review legacy-t." >/dev/null
write_assignments "$tmpdir/legacy-five.json" legacy-t legacy-t legacy-t legacy-t legacy-t
assert_rejected "legacy Round 2 must reject fewer than six workers" \
  "$LEDGER" prepare-round --run-dir "$legacy_run" --round 2 --assignments "$tmpdir/legacy-five.json"
write_assignments "$tmpdir/legacy-six.json" legacy-t legacy-t legacy-t legacy-t legacy-t legacy-t
"$LEDGER" prepare-round --run-dir "$legacy_run" --round 2 --assignments "$tmpdir/legacy-six.json" >/dev/null
python3 - "$legacy_run/round-01.json" "$legacy_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
state = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if round_doc["assignments"][0]["slot"] != "A1":
    raise SystemExit("legacy A-source records must remain readable")
if "review_portfolio_version" in state:
    raise SystemExit("legacy A review state must remain fieldless")
PY
assert_rejected "legacy protocol must retain the Round-4 cap" \
  "$LEDGER" prepare-round --run-dir "$legacy_run" --round 5 --assignments "$tmpdir/legacy-six.json" --user-approved

# Adaptive Round 1 is still fixed at six workers.
write_assignments "$tmpdir/not-six-round-one.json" t1 t2 t3 t4 t5
assert_rejected "adaptive Round 1 must require exactly six assignments" \
  "$LEDGER" prepare-round --run-dir "$protocol_run" --round 1 --assignments "$tmpdir/not-six-round-one.json"

# Adaptive Round 2 accepts variable consecutive C slots.
run_one="$(make_pending_run batch-one 1 0)"
write_assignments "$tmpdir/one.json" t1
"$LEDGER" prepare-round --run-dir "$run_one" --round 2 --assignments "$tmpdir/one.json" >/dev/null
assert_round_batch "$run_one" 2 1 "t1" "t1"
python3 - "$run_one/round-02.json" <<'PY'
import json
import sys
from pathlib import Path

assignment = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["assignments"][0]
if assignment.get("slot") != "C1" or assignment.get("source_slot") != "B1":
    raise SystemExit("a B1-sourced target must enter C1 follow-up review with its provenance")
PY

run_two="$(make_pending_run batch-two 2 0)"
write_assignments "$tmpdir/two.json" t1 t2
"$LEDGER" prepare-round --run-dir "$run_two" --round 2 --assignments "$tmpdir/two.json" >/dev/null
assert_round_batch "$run_two" 2 2 "t1,t2" "t1,t2"

run_five="$(make_pending_run batch-five 5 0)"
write_assignments "$tmpdir/five.json" t1 t2 t3 t4 t5
"$LEDGER" prepare-round --run-dir "$run_five" --round 2 --assignments "$tmpdir/five.json" >/dev/null
assert_round_batch "$run_five" 2 5 "t1,t2,t3,t4,t5" "t1,t2,t3,t4,t5"

run_seven="$(make_pending_run batch-seven 7 0)"
write_assignments "$tmpdir/six-active.json" t1 t2 t3 t4 t5 t6
"$LEDGER" prepare-round --run-dir "$run_seven" --round 2 --assignments "$tmpdir/six-active.json" >/dev/null
assert_round_batch "$run_seven" 2 6 "t1,t2,t3,t4,t5,t6,t7" "t1,t2,t3,t4,t5,t6"

# Outcomes belong exactly to active targets; replay carries unscheduled backlog.
complete_round "$run_seven" 2
empty_targets="$tmpdir/no-targets.json"
printf '[]\n' >"$empty_targets"
write_outcomes "$tmpdir/outcomes-extra.json" t1=accepted t2=accepted t3=accepted t4=accepted t5=accepted t6=accepted t7=accepted
write_synthesis "$tmpdir/synthesis-extra.json" "$empty_targets" "$tmpdir/outcomes-extra.json"
assert_rejected "unscheduled backlog targets must not appear in active-round outcomes" \
  "$LEDGER" record-synthesis --run-dir "$run_seven" --round 2 --synthesis "$tmpdir/synthesis-extra.json"
write_outcomes "$tmpdir/outcomes-missing.json" t1=accepted t2=accepted t3=accepted t4=accepted t5=accepted
write_synthesis "$tmpdir/synthesis-missing.json" "$empty_targets" "$tmpdir/outcomes-missing.json"
assert_rejected "every active target must have an outcome" \
  "$LEDGER" record-synthesis --run-dir "$run_seven" --round 2 --synthesis "$tmpdir/synthesis-missing.json"
write_outcomes "$tmpdir/outcomes-duplicate.json" t1=accepted t1=modified t2=accepted t3=accepted t4=accepted t5=accepted t6=accepted
write_synthesis "$tmpdir/synthesis-duplicate-outcomes.json" "$empty_targets" "$tmpdir/outcomes-duplicate.json"
assert_rejected "active targets must have exactly one outcome" \
  "$LEDGER" record-synthesis --run-dir "$run_seven" --round 2 --synthesis "$tmpdir/synthesis-duplicate-outcomes.json"
write_outcomes "$tmpdir/outcomes-six.json" t1=accepted t2=accepted t3=accepted t4=accepted t5=accepted t6=accepted
write_synthesis "$tmpdir/synthesis-six.json" "$empty_targets" "$tmpdir/outcomes-six.json"
"$LEDGER" record-synthesis --run-dir "$run_seven" --round 2 --synthesis "$tmpdir/synthesis-six.json" >/dev/null
python3 - "$run_seven/round-02.json" <<'PY'
import json
import sys
from pathlib import Path

synthesis = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["synthesis"]
if synthesis["cross_review_gate_status"] != "needs_cross_review":
    raise SystemExit("adaptive synthesis must derive needs_cross_review")
if synthesis["next_round_decision"] != "ask_user":
    raise SystemExit("Round 2 with backlog must derive ask_user")
PY
assert_rejected "adaptive finalize must reject a CLI decision that contradicts the derived decision" \
  "$LEDGER" finalize-round --run-dir "$run_seven" --round 2 --decision stop --summary "Contradiction"
"$LEDGER" finalize-round --run-dir "$run_seven" --round 2 --decision ask_user --summary "One target remains." >/dev/null
assert_rejected "Round 3 must require per-round approval" \
  "$LEDGER" prepare-round --run-dir "$run_seven" --round 3 --assignments "$tmpdir/one.json"
write_assignments "$tmpdir/t7-one.json" t7
"$LEDGER" prepare-round --run-dir "$run_seven" --round 3 --assignments "$tmpdir/t7-one.json" --user-approved >/dev/null
assert_round_batch "$run_seven" 3 1 "t7" "t7"

# Complete bundles are selected in canonical creation order and never split.
run_duals="$(make_pending_run four-duals 0 4)"
write_assignments "$tmpdir/three-dual-bundles.json" t1 t1 t2 t2 t3 t3
"$LEDGER" prepare-round --run-dir "$run_duals" --round 2 --assignments "$tmpdir/three-dual-bundles.json" >/dev/null
assert_round_batch "$run_duals" 2 6 "t1,t2,t3,t4" "t1,t2,t3"
write_assignments "$tmpdir/split-dual.json" t1 t1 t2 t2 t3
assert_rejected "an initial dual-review bundle must not be split" \
  "$LEDGER" prepare-round --run-dir "$run_duals" --round 2 --assignments "$tmpdir/split-dual.json"

mixed_targets="$tmpdir/mixed-targets.json"
write_targets "$mixed_targets" 5 1
mixed_run="$(init_run mixed-bundles)"
record_round_one_targets "$mixed_run" "$mixed_targets"
write_assignments "$tmpdir/five-before-dual.json" t1 t2 t3 t4 t5
"$LEDGER" prepare-round --run-dir "$mixed_run" --round 2 --assignments "$tmpdir/five-before-dual.json" >/dev/null
assert_round_batch "$mixed_run" 2 5 "t1,t2,t3,t4,t5,t6" "t1,t2,t3,t4,t5"

# Resolved targets leave the backlog; unresolved targets get exactly one later tie-break seat.
run_tiebreak="$(make_pending_run dual-tiebreak 0 1)"
write_assignments "$tmpdir/dual-initial.json" t1 t1
"$LEDGER" prepare-round --run-dir "$run_tiebreak" --round 2 --assignments "$tmpdir/dual-initial.json" >/dev/null
complete_round "$run_tiebreak" 2
write_outcomes "$tmpdir/t1-unresolved.json" t1=unresolved
write_synthesis "$tmpdir/tiebreak-r2.json" "$empty_targets" "$tmpdir/t1-unresolved.json"
"$LEDGER" record-synthesis --run-dir "$run_tiebreak" --round 2 --synthesis "$tmpdir/tiebreak-r2.json" >/dev/null
"$LEDGER" finalize-round --run-dir "$run_tiebreak" --round 2 --decision ask_user --summary "Authorize tie-break review." >/dev/null
"$LEDGER" prepare-round --run-dir "$run_tiebreak" --round 3 --assignments "$tmpdir/one.json" --user-approved >/dev/null
assert_round_batch "$run_tiebreak" 3 1 "t1" "t1"
complete_round "$run_tiebreak" 3
write_synthesis "$tmpdir/tiebreak-r3.json" "$empty_targets" "$tmpdir/t1-unresolved.json"
assert_rejected "dual tie-break cannot remain unresolved after its third reviewer" \
  "$LEDGER" record-synthesis --run-dir "$run_tiebreak" --round 3 --synthesis "$tmpdir/tiebreak-r3.json"
assert_rejected "rejected exhausted synthesis cannot be finalized" \
  "$LEDGER" finalize-round --run-dir "$run_tiebreak" --round 3 --decision ask_user \
  --summary "Textual review is exhausted."
write_outcomes "$tmpdir/t1-tiebreak-resolved.json" t1=accepted
write_synthesis "$tmpdir/tiebreak-r3-resolved.json" "$empty_targets" "$tmpdir/t1-tiebreak-resolved.json"
"$LEDGER" record-synthesis --run-dir "$run_tiebreak" --round 3 \
  --synthesis "$tmpdir/tiebreak-r3-resolved.json" >/dev/null
"$LEDGER" finalize-round --run-dir "$run_tiebreak" --round 3 --decision stop \
  --summary "Tie-break resolved the exhausted target." >/dev/null

run_resolution="$(make_pending_run resolution-replay 2 0)"
write_assignments "$tmpdir/resolution-two.json" t1 t2
"$LEDGER" prepare-round --run-dir "$run_resolution" --round 2 --assignments "$tmpdir/resolution-two.json" >/dev/null
complete_round "$run_resolution" 2
write_outcomes "$tmpdir/resolution-outcomes.json" t1=accepted t2=unresolved
write_synthesis "$tmpdir/resolution-synthesis.json" "$empty_targets" "$tmpdir/resolution-outcomes.json"
"$LEDGER" record-synthesis --run-dir "$run_resolution" --round 2 --synthesis "$tmpdir/resolution-synthesis.json" >/dev/null
"$LEDGER" finalize-round --run-dir "$run_resolution" --round 2 --decision ask_user --summary "t2 remains unresolved." >/dev/null
write_assignments "$tmpdir/t2-only.json" t2
"$LEDGER" prepare-round --run-dir "$run_resolution" --round 3 --assignments "$tmpdir/t2-only.json" --user-approved >/dev/null
assert_round_batch "$run_resolution" 3 1 "t2" "t2"

# Caller gate/decision assertions are not trusted, and stop cannot bypass backlog.
run_derived="$(init_run derived-gate)"
targets_derived="$tmpdir/derived-targets.json"
write_targets "$targets_derived" 1 0
"$LEDGER" prepare-round --run-dir "$run_derived" --round 1 --assignments "$six" >/dev/null
complete_round "$run_derived" 1
write_synthesis "$tmpdir/derived-valid.json" "$targets_derived" "$empty_targets"
python3 - "$tmpdir/derived-valid.json" "$tmpdir/missing-conflict-ref.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload["cross_review_targets"][0].pop("conflict_ref")
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
assert_rejected "every adaptive target must include conflict_ref, including explicit null" \
  "$LEDGER" record-synthesis --run-dir "$run_derived" --round 1 \
  --synthesis "$tmpdir/missing-conflict-ref.json"
write_outcomes "$tmpdir/round-one-fake-outcome.json" t1=accepted
write_synthesis "$tmpdir/round-one-fake-outcome-synthesis.json" \
  "$targets_derived" "$tmpdir/round-one-fake-outcome.json"
assert_rejected "a round with no active follow-up targets must not synthesize target outcomes" \
  "$LEDGER" record-synthesis --run-dir "$run_derived" --round 1 \
  --synthesis "$tmpdir/round-one-fake-outcome-synthesis.json"
python3 - "$tmpdir/derived-valid.json" "$tmpdir/derived-contradiction.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload["cross_review_gate_status"] = "clear"
payload["next_round_decision"] = "stop"
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
assert_rejected "adaptive synthesis must not trust caller gate or decision values" \
  "$LEDGER" record-synthesis --run-dir "$run_derived" --round 1 --synthesis "$tmpdir/derived-contradiction.json"
"$LEDGER" record-synthesis --run-dir "$run_derived" --round 1 --synthesis "$tmpdir/derived-valid.json" >/dev/null
assert_rejected "stop must be rejected while adaptive backlog remains" \
  "$LEDGER" finalize-round --run-dir "$run_derived" --round 1 --decision stop --summary "Do not stop"
"$LEDGER" finalize-round --run-dir "$run_derived" --round 1 --decision continue_round_2 --summary "Continue" >/dev/null

# Follow-up synthesis can introduce one fresh canonical target from a completed source assignment.
write_assignments "$tmpdir/derived-r2-assignment.json" t1
"$LEDGER" prepare-round --run-dir "$run_derived" --round 2 --assignments "$tmpdir/derived-r2-assignment.json" >/dev/null
complete_round "$run_derived" 2
fresh_targets="$tmpdir/fresh-targets.json"
python3 - "$fresh_targets" <<'PY'
import json
import sys
from pathlib import Path

target = [{
    "target_id": "t2",
    "source_slot": "C1",
    "claim": "Fresh follow-up claim",
    "why_decision_critical": "It changes the next decision",
    "review_policy": "single",
    "conflict_ref": None,
    "disposition": "pending",
}]
Path(sys.argv[1]).write_text(json.dumps(target, indent=2) + "\n", encoding="utf-8")
PY
bad_source="$tmpdir/bad-source-targets.json"
python3 - "$fresh_targets" "$bad_source" <<'PY'
import json
import sys
from pathlib import Path

targets = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
targets[0]["source_slot"] = "C9"
Path(sys.argv[2]).write_text(json.dumps(targets, indent=2) + "\n", encoding="utf-8")
PY
write_outcomes "$tmpdir/derived-r2-outcome.json" t1=accepted
write_synthesis "$tmpdir/bad-source-synthesis.json" "$bad_source" "$tmpdir/derived-r2-outcome.json"
assert_rejected "new target source_slot must resolve to a completed current-round assignment" \
  "$LEDGER" record-synthesis --run-dir "$run_derived" --round 2 --synthesis "$tmpdir/bad-source-synthesis.json"
duplicate_targets="$tmpdir/duplicate-origin-targets.json"
python3 - "$fresh_targets" "$duplicate_targets" <<'PY'
import json
import sys
from pathlib import Path

targets = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
targets[0]["target_id"] = "t1"
Path(sys.argv[2]).write_text(json.dumps(targets, indent=2) + "\n", encoding="utf-8")
PY
write_synthesis "$tmpdir/duplicate-origin-synthesis.json" "$duplicate_targets" "$tmpdir/derived-r2-outcome.json"
assert_rejected "duplicate canonical target_id across origin rounds must be rejected" \
  "$LEDGER" record-synthesis --run-dir "$run_derived" --round 2 --synthesis "$tmpdir/duplicate-origin-synthesis.json"
write_synthesis "$tmpdir/fresh-synthesis.json" "$fresh_targets" "$tmpdir/derived-r2-outcome.json"
"$LEDGER" record-synthesis --run-dir "$run_derived" --round 2 --synthesis "$tmpdir/fresh-synthesis.json" >/dev/null
python3 - "$run_derived/round-01.json" "$run_derived/round-02.json" <<'PY'
import json
import sys
from pathlib import Path

r1 = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
r2 = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if [item["target_id"] for item in r1["synthesis"]["cross_review_targets"]] != ["t1"]:
    raise SystemExit("origin Round 1 target was mutated or copied")
if [item["target_id"] for item in r2["synthesis"]["cross_review_targets"]] != ["t2"]:
    raise SystemExit("follow-up round must store only its fresh target")
PY
"$LEDGER" finalize-round --run-dir "$run_derived" --round 2 --decision ask_user --summary "Fresh t2 remains." >/dev/null

# Every Round 3+ batch needs its own approval, and adaptive runs have no absolute cap.
for round in 3 4 5; do
  previous="t$((round - 1))"
  current="t$round"
  write_assignments "$tmpdir/r${round}-assignment.json" "$previous"
  assert_rejected "Round $round must reject missing per-round approval" \
    "$LEDGER" prepare-round --run-dir "$run_derived" --round "$round" --assignments "$tmpdir/r${round}-assignment.json"
  "$LEDGER" prepare-round --run-dir "$run_derived" --round "$round" \
    --assignments "$tmpdir/r${round}-assignment.json" --user-approved >/dev/null
  complete_round "$run_derived" "$round"
  write_outcomes "$tmpdir/r${round}-outcomes.json" "$previous=accepted"
  if [[ "$round" -lt 5 ]]; then
    python3 - "$tmpdir/r${round}-targets.json" "$current" <<'PY'
import json
import sys
from pathlib import Path

target_id = sys.argv[2]
target = [{
    "target_id": target_id,
    "source_slot": "C1",
    "claim": f"Fresh claim {target_id}",
    "why_decision_critical": f"Why {target_id} changes the decision",
    "review_policy": "single",
    "conflict_ref": None,
    "disposition": "pending",
}]
Path(sys.argv[1]).write_text(json.dumps(target, indent=2) + "\n", encoding="utf-8")
PY
    write_synthesis "$tmpdir/r${round}-synthesis.json" "$tmpdir/r${round}-targets.json" "$tmpdir/r${round}-outcomes.json"
    "$LEDGER" record-synthesis --run-dir "$run_derived" --round "$round" \
      --synthesis "$tmpdir/r${round}-synthesis.json" >/dev/null
    "$LEDGER" finalize-round --run-dir "$run_derived" --round "$round" --decision ask_user \
      --summary "Authorize the next fresh batch." >/dev/null
  else
    write_synthesis "$tmpdir/r${round}-synthesis.json" "$empty_targets" "$tmpdir/r${round}-outcomes.json"
    "$LEDGER" record-synthesis --run-dir "$run_derived" --round "$round" \
      --synthesis "$tmpdir/r${round}-synthesis.json" >/dev/null
    "$LEDGER" finalize-round --run-dir "$run_derived" --round "$round" --decision stop \
      --summary "Backlog resolved in Round 5." >/dev/null
  fi
done

# Default adaptive runs accept needs_revision while the derived backlog continues or asks the user.
objective_run="$(init_run adaptive-needs-revision)"
objective_targets="$tmpdir/adaptive-needs-revision-targets.json"
write_targets "$objective_targets" 1 0
"$LEDGER" prepare-round --run-dir "$objective_run" --round 1 --assignments "$six" >/dev/null
complete_round "$objective_run" 1
write_needs_revision_synthesis \
  "$tmpdir/adaptive-needs-revision-r1.json" \
  "$objective_targets" \
  "$empty_targets" \
  "The pending target must be reviewed before the objective is satisfied." \
  "Resolve target t1."
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 \
  --synthesis "$tmpdir/adaptive-needs-revision-r1.json" >/dev/null
python3 - "$objective_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

synthesis = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["synthesis"]
if synthesis["objective_alignment"]["status"] != "needs_revision":
    raise SystemExit("adaptive Round 1 did not preserve needs_revision")
if synthesis["next_round_decision"] != "continue_round_2":
    raise SystemExit("adaptive Round 1 did not derive continue_round_2")
PY
"$LEDGER" finalize-round --run-dir "$objective_run" --round 1 \
  --decision continue_round_2 --summary "Review target t1." >/dev/null

write_assignments "$tmpdir/adaptive-needs-revision-r2-assignments.json" t1
"$LEDGER" prepare-round --run-dir "$objective_run" --round 2 \
  --assignments "$tmpdir/adaptive-needs-revision-r2-assignments.json" >/dev/null
complete_round "$objective_run" 2
write_outcomes "$tmpdir/adaptive-needs-revision-r2-outcomes.json" t1=unresolved
write_needs_revision_synthesis \
  "$tmpdir/adaptive-needs-revision-r2.json" \
  "$empty_targets" \
  "$tmpdir/adaptive-needs-revision-r2-outcomes.json" \
  "The unresolved target needs the user's approval for a tie-break review." \
  "Decide whether to authorize the tie-break."
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 2 \
  --synthesis "$tmpdir/adaptive-needs-revision-r2.json" >/dev/null
python3 - "$objective_run/round-02.json" <<'PY'
import json
import sys
from pathlib import Path

synthesis = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["synthesis"]
if synthesis["objective_alignment"]["status"] != "needs_revision":
    raise SystemExit("adaptive Round 2 did not preserve needs_revision")
if synthesis["next_round_decision"] != "ask_user":
    raise SystemExit("adaptive Round 2 did not derive ask_user")
PY
"$LEDGER" finalize-round --run-dir "$objective_run" --round 2 \
  --decision ask_user --summary "Authorize the tie-break review." >/dev/null

echo "adaptive follow-up protocol looks good"
