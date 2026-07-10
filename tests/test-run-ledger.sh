#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="$REPO_ROOT/scripts/run-ledger"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

init_legacy() {
  local run_dir
  run_dir="$("$LEDGER" init "$@")" || return
  python3 - "$run_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state.pop("protocol_version", None)
path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
  printf '%s\n' "$run_dir"
}

root="$tmpdir/.superpowers/multi-agent-analysis"

run_dir="$(init_legacy \
  --root "$root" \
  --mode review \
  --target docs/plan.md \
  --objective "Decide whether the implementation plan is ready" \
  --spawn-tool multi_agent_v1.spawn_agent \
  --wait-tool multi_agent_v1.wait_agent \
  --close-tool multi_agent_v1.close_agent \
  --cwd "$REPO_ROOT" \
  --title "Plan review")"

for path in \
  "$root/.gitignore" \
  "$run_dir/brief.md" \
  "$run_dir/ledger.md" \
  "$run_dir/state.json"
do
  [[ -f "$path" ]] || {
    echo "missing expected ledger file: $path" >&2
    exit 1
  }
done

python3 - "$run_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in [
    "version",
    "run_id",
    "mode",
    "status",
    "tooling",
    "expected_agents_per_round",
    "round_cap",
]:
    if key not in state:
        raise SystemExit(f"state.json missing {key}")
if state["mode"] != "review":
    raise SystemExit("state.json mode mismatch")
if state["expected_agents_per_round"] != 6:
    raise SystemExit("expected_agents_per_round must be 6")
if state["round_cap"] != 4:
    raise SystemExit("round_cap must be 4")
for key in ["spawn", "wait", "close"]:
    if key not in state["tooling"]:
        raise SystemExit(f"tooling missing {key}")
PY

if init_legacy \
  --root "$tmpdir/.superpowers/bad-tooling" \
  --mode review \
  --target docs/plan.md \
  --objective "Reject blank tool names" \
  --spawn-tool "   " \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Bad tooling test" >/dev/null 2>&1; then
  echo "init should reject blank tool names" >&2
  exit 1
fi

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

fill_synthesis() {
  local round_json="$1"
  local decision="$2"
  local summary="$3"
  local round_dir
  local round_file
  local round_number
  local synthesis_file
  round_dir="$(dirname "$round_json")"
  round_file="$(basename "$round_json")"
  round_number="${round_file#round-}"
  round_number="${round_number%.json}"
  round_number="$((10#$round_number))"
  synthesis_file="$tmpdir/synthesis-$round_number-$decision.json"
  python3 - "$synthesis_file" "$decision" "$summary" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
decision = sys.argv[2]
summary = sys.argv[3]
synthesis = {}
synthesis["convergence"] = ["Test convergence."]
synthesis["disagreement"] = ["Test disagreement."]
synthesis["critical_disagreements"] = []
synthesis["cannot_verify"] = []
synthesis["high_impact_low_evidence"] = []
synthesis["action_list"] = ["Test action."]
synthesis["expected_value_of_another_round"] = (
    "A follow-up round only pays off if unresolved blockers remain."
)
synthesis["next_round_decision"] = decision
if decision == "stop":
    synthesis["objective_alignment"] = {
        "status": "aligned",
        "rationale": "The synthesis answers the original objective and retains the stated constraints.",
        "unmet_requirements": [],
    }
else:
    synthesis["objective_alignment"] = {
        "status": "needs_revision",
        "rationale": "The next round must resolve the remaining requirement before the objective is satisfied.",
        "unmet_requirements": ["Resolve the remaining requirement."],
    }
if decision == "stop":
    synthesis["stop_reason"] = summary
else:
    synthesis["next_round_question"] = summary
path.write_text(json.dumps(synthesis, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  "$LEDGER" record-synthesis \
    --run-dir "$round_dir" \
    --round "$round_number" \
    --synthesis "$synthesis_file" >/dev/null
}

with_objective_alignment() {
  local path="$1"
  local status="$2"
  local rationale="$3"
  local unmet_requirements="$4"
  python3 - "$path" "$status" "$rationale" "$unmet_requirements" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["objective_alignment"] = {
    "status": sys.argv[2],
    "rationale": sys.argv[3],
    "unmet_requirements": json.loads(sys.argv[4]),
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

create_completed_cross_review_round() {
  cross_root="$tmpdir/.superpowers/cross-review"
  cross_run="$(init_legacy \
    --root "$cross_root" \
    --mode review \
    --target "plan" \
    --objective "Review cross-review gate" \
    --spawn-tool spawn \
    --wait-tool wait \
    --close-tool close \
    --title "Cross review gate")"

  "$LEDGER" prepare-round --run-dir "$cross_run" --round 1 --assignments "$six" >/dev/null
  for slot in A1 A2 A3 A4 A5 A6; do
    "$LEDGER" record-spawn --run-dir "$cross_run" --round 1 --slot "$slot" --agent-id "agent-$slot" --status spawned >/dev/null
    "$LEDGER" record-result --run-dir "$cross_run" --round 1 --slot "$slot" --status completed --summary "$slot result" >/dev/null
    "$LEDGER" record-close --run-dir "$cross_run" --round 1 --slot "$slot" --status closed >/dev/null
  done
}

"$LEDGER" prepare-round \
  --run-dir "$run_dir" \
  --round 1 \
  --assignments "$six" >/dev/null

for path in "$run_dir/round-01.json" "$run_dir/round-01.md"; do
  [[ -f "$path" ]] || {
    echo "missing expected round file: $path" >&2
    exit 1
  }
done

python3 - "$run_dir/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments = round_doc.get("assignments")
if not isinstance(assignments, list):
    raise SystemExit("round-01.json assignments must be a list")
if len(assignments) != 6:
    raise SystemExit("round-01.json must contain exactly six assignments")
if [assignment["slot"] for assignment in assignments] != ["A1", "A2", "A3", "A4", "A5", "A6"]:
    raise SystemExit("review round 1 slots must be A1-A6 in order")
for assignment in assignments:
    for key in [
        "slot",
        "lens",
        "question",
        "spawn_tool",
        "wait_tool",
        "close_tool",
        "spawn_status",
        "result_status",
        "close_status",
    ]:
        if key not in assignment:
            raise SystemExit(f"assignment missing {key}")
for key in [
    "convergence",
    "disagreement",
    "critical_disagreements",
    "cannot_verify",
    "high_impact_low_evidence",
    "action_list",
    "expected_value_of_another_round",
    "next_round_decision",
]:
    if key not in round_doc.get("synthesis", {}):
        raise SystemExit(f"synthesis missing {key}")
events = round_doc.get("events")
if not isinstance(events, list) or len(events) != 1:
    raise SystemExit("prepared round must contain one canonical prepare event")
if events[0].get("event_id") != "r01-round-prepare":
    raise SystemExit("prepare event_id must be deterministic")
if events[0].get("event") != "prepare" or events[0].get("slot") != "round":
    raise SystemExit("prepare event shape mismatch")
PY

premature_synthesis="$tmpdir/premature-synthesis.json"
python3 - "$premature_synthesis" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "convergence": ["No evidence exists yet."],
            "action_list": ["Do not accept this."],
            "expected_value_of_another_round": "Unknown before lifecycle completion.",
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

if "$LEDGER" record-synthesis \
  --run-dir "$run_dir" \
  --round 1 \
  --synthesis "$premature_synthesis" >/dev/null 2>&1; then
  echo "record-synthesis should reject rounds before lifecycle completion" >&2
  exit 1
fi

injected_six="$tmpdir/injected-lifecycle.json"
python3 - "$six" "$injected_six" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for assignment in assignments:
    slot = assignment["slot"]
    assignment.update(
        {
            "agent_id": f"injected-{slot}",
            "spawn_status": "spawned",
            "spawn_recorded_at": "2026-01-01T00:00:01+00:00",
            "result_status": "completed",
            "result_summary": f"Injected {slot} result",
            "result_recorded_at": "2026-01-01T00:00:02+00:00",
            "close_status": "closed",
            "close_recorded_at": "2026-01-01T00:00:03+00:00",
        }
    )
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

injected_run="$(init_legacy \
  --root "$tmpdir/.superpowers/injected-lifecycle" \
  --mode review \
  --target docs/plan.md \
  --objective "Reject injected assignment lifecycle state" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Injected lifecycle test")"
"$LEDGER" prepare-round \
  --run-dir "$injected_run" \
  --round 1 \
  --assignments "$injected_six" >/dev/null

if "$LEDGER" record-synthesis \
  --run-dir "$injected_run" \
  --round 1 \
  --synthesis "$premature_synthesis" >/dev/null 2>&1; then
  echo "record-synthesis reached synthesis from injected assignment lifecycle fields" >&2
  exit 1
fi

python3 - "$injected_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for assignment in round_doc["assignments"]:
    if assignment["agent_id"] is not None:
        raise SystemExit("prepare-round preserved an injected agent_id")
    if [assignment["spawn_status"], assignment["result_status"], assignment["close_status"]] != [
        "pending",
        "pending",
        "pending",
    ]:
        raise SystemExit("prepare-round preserved injected lifecycle statuses")
    if assignment["result_summary"] != "":
        raise SystemExit("prepare-round preserved an injected result summary")
    for key in ("spawn_recorded_at", "result_recorded_at", "close_recorded_at"):
        if key in assignment:
            raise SystemExit(f"prepare-round preserved injected {key}")
PY

invalid_status_run="$(init_legacy \
  --root "$tmpdir/.superpowers/invalid-status" \
  --mode review \
  --target docs/plan.md \
  --objective "Reject invalid lifecycle statuses" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Invalid status test")"

"$LEDGER" prepare-round \
  --run-dir "$invalid_status_run" \
  --round 1 \
  --assignments "$six" >/dev/null

if "$LEDGER" record-spawn \
  --run-dir "$invalid_status_run" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
  --status bogus >/dev/null 2>&1; then
  echo "record-spawn should reject unknown statuses" >&2
  exit 1
fi

"$LEDGER" record-spawn \
  --run-dir "$invalid_status_run" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
  --status spawned >/dev/null

if "$LEDGER" record-result \
  --run-dir "$invalid_status_run" \
  --round 1 \
  --slot A1 \
  --status bogus \
  --summary "Invalid result status." >/dev/null 2>&1; then
  echo "record-result should reject unknown statuses" >&2
  exit 1
fi

"$LEDGER" record-result \
  --run-dir "$invalid_status_run" \
  --round 1 \
  --slot A1 \
  --status completed \
  --summary "Valid result." >/dev/null

if "$LEDGER" record-close \
  --run-dir "$invalid_status_run" \
  --round 1 \
  --slot A1 \
  --status bogus >/dev/null 2>&1; then
  echo "record-close should reject unknown statuses" >&2
  exit 1
fi

abnormal_run="$(init_legacy \
  --root "$tmpdir/.superpowers/abnormal-close" \
  --mode review \
  --target docs/plan.md \
  --objective "Allow abnormal close without a result" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Abnormal close test")"

"$LEDGER" prepare-round \
  --run-dir "$abnormal_run" \
  --round 1 \
  --assignments "$six" >/dev/null

"$LEDGER" record-spawn \
  --run-dir "$abnormal_run" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
  --status spawned >/dev/null

"$LEDGER" record-close \
  --run-dir "$abnormal_run" \
  --round 1 \
  --slot A1 \
  --status failed >/dev/null

"$LEDGER" finalize-round \
  --run-dir "$abnormal_run" \
  --round 1 \
  --decision stop \
  --summary "Worker closed abnormally before returning a result." \
  --blocked >/dev/null

if "$LEDGER" finalize-round \
  --run-dir "$abnormal_run" \
  --round 1 \
  --decision stop \
  --summary "Blocked rounds should not finalize twice." \
  --blocked >/dev/null 2>&1; then
  echo "finalize-round should reject already blocked rounds" >&2
  exit 1
fi

"$LEDGER" record-spawn \
  --run-dir "$run_dir" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
  --status spawned >/dev/null

if "$LEDGER" record-close \
  --run-dir "$run_dir" \
  --round 1 \
  --slot A1 \
  --status closed >/dev/null 2>&1; then
  echo "record-close should reject slots without a result record" >&2
  exit 1
fi

"$LEDGER" record-result \
  --run-dir "$run_dir" \
  --round 1 \
  --slot A1 \
  --status completed \
  --summary "A1 returned a first-principles finding." >/dev/null

"$LEDGER" record-close \
  --run-dir "$run_dir" \
  --round 1 \
  --slot A1 \
  --status closed >/dev/null

if "$LEDGER" record-result \
  --run-dir "$run_dir" \
  --round 1 \
  --slot A2 \
  --status completed \
  --summary "Impossible result before spawn." >/dev/null 2>&1; then
  echo "record-result should reject slots that have not spawned" >&2
  exit 1
fi

if "$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 1 \
  --decision stop \
  --summary "Incomplete round should not finalize." >/dev/null 2>&1; then
  echo "finalize-round should reject incomplete rounds unless blocked" >&2
  exit 1
fi

blocked_run="$(init_legacy \
  --root "$tmpdir/.superpowers/blocked" \
  --mode review \
  --target docs/plan.md \
  --objective "Test blocked lifecycle handling" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Blocked lifecycle test")"

"$LEDGER" prepare-round \
  --run-dir "$blocked_run" \
  --round 1 \
  --assignments "$six" >/dev/null

if "$LEDGER" record-spawn \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --status spawned >/dev/null 2>&1; then
  echo "record-spawn should require agent-id when status is spawned" >&2
  exit 1
fi

if "$LEDGER" record-spawn \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --agent-id "   " \
  --status spawned >/dev/null 2>&1; then
  echo "record-spawn should reject blank agent-id when status is spawned" >&2
  exit 1
fi

if "$LEDGER" record-spawn \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
  --status failed >/dev/null 2>&1; then
  echo "record-spawn should reject agent-id when status is failed" >&2
  exit 1
fi

"$LEDGER" record-spawn \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --status failed >/dev/null

python3 - "$blocked_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if state["next_action"] != "finalize_blocked_round":
    raise SystemExit("failed spawn should point next_action at finalize_blocked_round")
PY

if "$LEDGER" record-result \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --status completed \
  --summary "Impossible result after failed spawn." >/dev/null 2>&1; then
  echo "record-result should reject slots whose spawn did not succeed" >&2
  exit 1
fi

if "$LEDGER" record-close \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --status closed >/dev/null 2>&1; then
  echo "record-close should reject slots whose spawn did not succeed" >&2
  exit 1
fi

if "$LEDGER" finalize-round \
  --run-dir "$blocked_run" \
  --round 1 \
  --decision continue_round_2 \
  --summary "Blocked rounds cannot continue." \
  --blocked >/dev/null 2>&1; then
  echo "blocked finalize should require --decision stop" >&2
  exit 1
fi

"$LEDGER" finalize-round \
  --run-dir "$blocked_run" \
  --round 1 \
  --decision stop \
  --summary "Worker dispatch failed; user input is required." \
  --blocked >/dev/null

python3 - "$blocked_run/state.json" "$blocked_run/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
round_doc = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if state["status"] != "blocked":
    raise SystemExit("blocked finalize did not persist blocked run status")
if state["next_action"] != "blocked":
    raise SystemExit("blocked finalize did not persist blocked next_action")
if round_doc["status"] != "blocked":
    raise SystemExit("blocked finalize did not persist blocked round status")
if "dispatch failed" not in round_doc["synthesis"].get("stop_reason", ""):
    raise SystemExit("blocked finalize did not persist stop reason")
PY

if "$LEDGER" record-spawn \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A2 \
  --agent-id agent-a2 \
  --status spawned >/dev/null 2>&1; then
  echo "record-spawn should reject terminal blocked rounds" >&2
  exit 1
fi

if "$LEDGER" prepare-round \
  --run-dir "$blocked_run" \
  --round 2 \
  --assignments "$six" >/dev/null 2>&1; then
  echo "prepare-round should reject runs already marked blocked" >&2
  exit 1
fi

planned_run="$(init_legacy \
  --root "$tmpdir/.superpowers/planned-dispatch" \
  --mode review \
  --target docs/plan.md \
  --objective "Record fresh dispatch intent before spawning" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Planned dispatch test")"

"$LEDGER" prepare-round --run-dir "$planned_run" --round 1 --assignments "$six" >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A1 >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A1 >/dev/null

python3 - "$planned_run" "$LEDGER" <<'PY'
import json
import subprocess
import sys

status = json.loads(subprocess.check_output([sys.argv[2], "status", "--run-dir", sys.argv[1]]))
counts = status["rounds"]["round-01"]
if counts["planned_dispatches"] != 1:
    raise SystemExit("plan-dispatch must expose one planned dispatch")
if counts["unknown_dispatches"] != 0:
    raise SystemExit("newly planned dispatch must not be unknown")
if status["next_action"] != "resolve_planned_dispatch":
    raise SystemExit("planned dispatch must report resolve_planned_dispatch")
PY

if "$LEDGER" record-synthesis --run-dir "$planned_run" --round 1 \
  --synthesis "$premature_synthesis" >/dev/null 2>&1; then
  echo "record-synthesis should reject a round with planned dispatch intent" >&2
  exit 1
fi
if "$LEDGER" finalize-round --run-dir "$planned_run" --round 1 --decision stop \
  --summary "Planned dispatch is unresolved." --blocked >/dev/null 2>&1; then
  echo "finalize-round should reject a round with planned dispatch intent" >&2
  exit 1
fi
if "$LEDGER" record-spawn --run-dir "$planned_run" --round 1 --slot A1 \
  --status unknown --agent-id agent-a1 >/dev/null 2>&1; then
  echo "record-spawn should reject agent-id when status is unknown" >&2
  exit 1
fi

"$LEDGER" record-spawn --run-dir "$planned_run" --round 1 --slot A1 --status unknown >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A1 >/dev/null
if "$LEDGER" record-spawn --run-dir "$planned_run" --round 1 --slot A1 \
  --status spawned --agent-id replacement-a1 >/dev/null 2>&1; then
  echo "unknown dispatch must not be retried or replaced" >&2
  exit 1
fi

"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A2 >/dev/null
"$LEDGER" record-spawn --run-dir "$planned_run" --round 1 --slot A2 \
  --status spawned --agent-id agent-a2 >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A2 >/dev/null
"$LEDGER" record-result --run-dir "$planned_run" --round 1 --slot A2 \
  --status completed --summary "Known worker result." >/dev/null
"$LEDGER" record-close --run-dir "$planned_run" --round 1 --slot A2 --status closed >/dev/null

"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A3 >/dev/null
"$LEDGER" record-spawn --run-dir "$planned_run" --round 1 --slot A3 --status failed >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A3 >/dev/null

python3 - "$planned_run" "$LEDGER" <<'PY'
import json
import subprocess
import sys

status = json.loads(subprocess.check_output([sys.argv[2], "status", "--run-dir", sys.argv[1]]))
counts = status["rounds"]["round-01"]
if counts["planned_dispatches"] != 0 or counts["unknown_dispatches"] != 1:
    raise SystemExit("resolved dispatch intent must retain one explicit unknown dispatch")
if status["next_action"] != "finalize_blocked_round":
    raise SystemExit("unknown dispatch must require blocked finalization after known workers drain")
PY

"$LEDGER" finalize-round --run-dir "$planned_run" --round 1 --decision stop \
  --summary "Dispatch outcome could not be proven; known workers were drained." --blocked >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A1 >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A2 >/dev/null
"$LEDGER" plan-dispatch --run-dir "$planned_run" --round 1 --slot A3 >/dev/null

open_blocked_run="$(init_legacy \
  --root "$tmpdir/.superpowers/open-blocked" \
  --mode review \
  --target docs/plan.md \
  --objective "Reject blocked finalization with open workers" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Open blocked test")"

"$LEDGER" prepare-round \
  --run-dir "$open_blocked_run" \
  --round 1 \
  --assignments "$six" >/dev/null

"$LEDGER" record-spawn \
  --run-dir "$open_blocked_run" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
  --status spawned >/dev/null

"$LEDGER" record-spawn \
  --run-dir "$open_blocked_run" \
  --round 1 \
  --slot A2 \
  --status failed >/dev/null

if "$LEDGER" finalize-round \
  --run-dir "$open_blocked_run" \
  --round 1 \
  --decision stop \
  --summary "A2 failed while A1 is still open." \
  --blocked >/dev/null 2>&1; then
  echo "blocked finalize should reject open spawned workers" >&2
  exit 1
fi

no_activity_blocked_run="$(init_legacy \
  --root "$tmpdir/.superpowers/no-activity-blocked" \
  --mode review \
  --target docs/plan.md \
  --objective "Reject fabricated blocked rounds" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "No activity blocked test")"

"$LEDGER" prepare-round \
  --run-dir "$no_activity_blocked_run" \
  --round 1 \
  --assignments "$six" >/dev/null

if "$LEDGER" finalize-round \
  --run-dir "$no_activity_blocked_run" \
  --round 1 \
  --decision stop \
  --summary "No worker activity happened." \
  --blocked >/dev/null 2>&1; then
  echo "blocked finalize should require recorded lifecycle failure evidence" >&2
  exit 1
fi

failed_result_run="$(init_legacy \
  --root "$tmpdir/.superpowers/failed-result" \
  --mode review \
  --target docs/plan.md \
  --objective "Do not count failed results as usable" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Failed result test")"

"$LEDGER" prepare-round \
  --run-dir "$failed_result_run" \
  --round 1 \
  --assignments "$six" >/dev/null

for slot in A1 A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn \
    --run-dir "$failed_result_run" \
    --round 1 \
    --slot "$slot" \
    --agent-id "agent-${slot,,}" \
    --status spawned >/dev/null

  "$LEDGER" record-result \
    --run-dir "$failed_result_run" \
    --round 1 \
    --slot "$slot" \
    --status failed \
    --summary "$slot returned a failed result." >/dev/null

  "$LEDGER" record-close \
    --run-dir "$failed_result_run" \
    --round 1 \
    --slot "$slot" \
    --status closed >/dev/null
done

if "$LEDGER" record-synthesis \
  --run-dir "$failed_result_run" \
  --round 1 \
  --synthesis "$premature_synthesis" >/dev/null 2>&1; then
  echo "record-synthesis should reject rounds without six completed usable results" >&2
  exit 1
fi

if "$LEDGER" finalize-round \
  --run-dir "$failed_result_run" \
  --round 1 \
  --decision stop \
  --summary "Failed results are not usable." >/dev/null 2>&1; then
  echo "finalize-round should reject failed results as unusable" >&2
  exit 1
fi

python3 - "$run_dir/round-01.json" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignment = round_doc["assignments"][0]
if assignment["agent_id"] != "agent-a1":
    raise SystemExit("record-spawn did not persist agent_id")
if assignment["spawn_status"] != "spawned":
    raise SystemExit("record-spawn did not persist status")
if assignment["result_status"] != "completed":
    raise SystemExit("record-result did not persist status")
if "first-principles" not in assignment["result_summary"]:
    raise SystemExit("record-result did not persist summary")
if assignment["close_status"] != "closed":
    raise SystemExit("record-close did not persist close status")
event_ids = {item.get("event_id") for item in round_doc.get("events", [])}
expected_ids = {
    "r01-round-prepare",
    "r01-A1-spawn",
    "r01-A1-result",
    "r01-A1-close",
}
if not expected_ids.issubset(event_ids):
    raise SystemExit("lifecycle events must use deterministic canonical event ids")
PY

status_json="$("$LEDGER" status --run-dir "$run_dir")"
python3 - "$status_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
if status["current_round"] != 1:
    raise SystemExit("status current_round mismatch")
if status["rounds"]["round-01"]["spawned"] != 1:
    raise SystemExit("status spawned count mismatch")
if status["rounds"]["round-01"]["closed"] != 1:
    raise SystemExit("status closed count mismatch")
PY

python3 - "$run_dir/round-01-synthesis.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({"not": "a round"}) + "\n", encoding="utf-8")
PY

status_json="$("$LEDGER" status --run-dir "$run_dir")"
python3 - "$status_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
if "round-01-synthesis" in status["rounds"]:
    raise SystemExit("status should ignore round sidecar JSON files")
PY

five="$tmpdir/five.json"
python3 - "$six" "$five" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
Path(sys.argv[2]).write_text(
    json.dumps(assignments[:5], indent=2) + "\n",
    encoding="utf-8",
)
PY

if "$LEDGER" prepare-round --run-dir "$run_dir" --round 2 --assignments "$five" >/dev/null 2>&1; then
  echo "prepare-round should reject assignment counts other than six" >&2
  exit 1
fi
[[ ! -f "$run_dir/round-02.json" ]] || {
  echo "failed prepare-round should not leave round-02.json" >&2
  exit 1
}

duplicate="$tmpdir/duplicate.json"
python3 - "$six" "$duplicate" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments[1]["slot"] = "A1"
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

duplicate_run="$(init_legacy \
  --root "$tmpdir/.superpowers/duplicate" \
  --mode review \
  --target docs/plan.md \
  --objective "Test duplicate slots" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Duplicate slot test")"

if "$LEDGER" prepare-round --run-dir "$duplicate_run" --round 1 --assignments "$duplicate" >/dev/null 2>&1; then
  echo "prepare-round should reject duplicate slots" >&2
  exit 1
fi

if "$LEDGER" prepare-round --run-dir "$run_dir" --round 5 --assignments "$six" >/dev/null 2>&1; then
  echo "prepare-round should reject rounds beyond the cap" >&2
  exit 1
fi

if "$LEDGER" prepare-round --run-dir "$run_dir" --round 3 --assignments "$six" >/dev/null 2>&1; then
  echo "prepare-round should reject skipped rounds on a fresh run" >&2
  exit 1
fi

for slot in A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn \
    --run-dir "$run_dir" \
    --round 1 \
    --slot "$slot" \
    --agent-id "agent-${slot,,}" \
    --status spawned >/dev/null

  "$LEDGER" record-result \
    --run-dir "$run_dir" \
    --round 1 \
    --slot "$slot" \
    --status completed \
    --summary "$slot returned a usable finding." >/dev/null

  "$LEDGER" record-close \
    --run-dir "$run_dir" \
    --round 1 \
    --slot "$slot" \
    --status closed >/dev/null
done

if "$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 1 \
  --decision stop \
  --summary "Complete round should not be marked blocked." \
  --blocked >/dev/null 2>&1; then
  echo "finalize-round should reject --blocked for complete rounds" >&2
  exit 1
fi

if "$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 1 \
  --decision continue_round_2 \
  --summary "Round two is justified for test coverage." >/dev/null 2>&1; then
  echo "finalize-round should reject complete rounds until synthesis is populated" >&2
  exit 1
fi

fill_synthesis "$run_dir/round-01.json" continue_round_2 "Round two is justified for test coverage."
if "$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 1 \
  --decision ask_user \
  --summary "Round one cannot ask for user approval." >/dev/null 2>&1; then
  echo "finalize-round should reject round 1 ask_user decisions" >&2
  exit 1
fi

"$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 1 \
  --decision continue_round_2 \
  --summary "Round two is justified for test coverage." >/dev/null

python3 - "$run_dir/round-01.json" "$run_dir/ledger.md" <<'PY'
import json
import sys
from pathlib import Path

round_doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
event_ids = [item["event_id"] for item in round_doc["events"]]
if "r01-round-finalize" not in event_ids:
    raise SystemExit("finalization must be a canonical round event")
if not any(identifier.startswith("r01-round-synthesis-") for identifier in event_ids):
    raise SystemExit("synthesis event id must include its canonical payload digest")
ledger = Path(sys.argv[2]).read_text(encoding="utf-8")
for identifier in event_ids:
    if ledger.count(identifier) != 1:
        raise SystemExit(f"ledger projection must contain {identifier} exactly once")
PY

python3 - "$run_dir/round-01.md" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "Test convergence." not in text:
    raise SystemExit("round markdown should render synthesis convergence")
if "Test action." not in text:
    raise SystemExit("round markdown should render synthesis actions")
PY

round2="$tmpdir/round2.json"
cat >"$round2" <<'JSON'
[
  {"slot": "R2-1", "lens": "Follow-up 1", "question": "What needs follow-up 1?"},
  {"slot": "R2-2", "lens": "Follow-up 2", "question": "What needs follow-up 2?"},
  {"slot": "R2-3", "lens": "Follow-up 3", "question": "What needs follow-up 3?"},
  {"slot": "R2-4", "lens": "Follow-up 4", "question": "What needs follow-up 4?"},
  {"slot": "R2-5", "lens": "Follow-up 5", "question": "What needs follow-up 5?"},
  {"slot": "R2-6", "lens": "Follow-up 6", "question": "What needs follow-up 6?"}
]
JSON

"$LEDGER" prepare-round \
  --run-dir "$run_dir" \
  --round 2 \
  --assignments "$round2" >/dev/null

for slot in R2-1 R2-2 R2-3 R2-4 R2-5 R2-6; do
  "$LEDGER" record-spawn \
    --run-dir "$run_dir" \
    --round 2 \
    --slot "$slot" \
    --agent-id "agent-${slot,,}" \
    --status spawned >/dev/null

  "$LEDGER" record-result \
    --run-dir "$run_dir" \
    --round 2 \
    --slot "$slot" \
    --status completed \
    --summary "$slot returned a follow-up finding." >/dev/null

  "$LEDGER" record-close \
    --run-dir "$run_dir" \
    --round 2 \
    --slot "$slot" \
    --status closed >/dev/null
done

fill_synthesis "$run_dir/round-02.json" ask_user "Round three needs explicit approval."
if "$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 2 \
  --decision continue_round_2 \
  --summary "Round two cannot request continue_round_2." >/dev/null 2>&1; then
  echo "finalize-round should reject round 2 continue_round_2 decisions" >&2
  exit 1
fi

"$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 2 \
  --decision ask_user \
  --summary "Round three needs explicit approval." >/dev/null

if "$LEDGER" finalize-round \
  --run-dir "$run_dir" \
  --round 2 \
  --decision stop \
  --summary "Finalized rounds should not be rewritten." >/dev/null 2>&1; then
  echo "finalize-round should reject already finalized rounds" >&2
  exit 1
fi

round3="$tmpdir/round3.json"
cat >"$round3" <<'JSON'
[
  {"slot": "C1", "lens": "Approved Follow-up 1", "question": "What needs approved follow-up 1?"},
  {"slot": "C2", "lens": "Approved Follow-up 2", "question": "What needs approved follow-up 2?"},
  {"slot": "C3", "lens": "Approved Follow-up 3", "question": "What needs approved follow-up 3?"},
  {"slot": "C4", "lens": "Approved Follow-up 4", "question": "What needs approved follow-up 4?"},
  {"slot": "C5", "lens": "Approved Follow-up 5", "question": "What needs approved follow-up 5?"},
  {"slot": "C6", "lens": "Approved Follow-up 6", "question": "What needs approved follow-up 6?"}
]
JSON

if "$LEDGER" prepare-round --run-dir "$run_dir" --round 3 --assignments "$round3" >/dev/null 2>&1; then
  echo "prepare-round should reject round 3 without user approval" >&2
  exit 1
fi

"$LEDGER" prepare-round \
  --run-dir "$run_dir" \
  --round 3 \
  --assignments "$round3" \
  --user-approved >/dev/null

divergent_root="$tmpdir/.superpowers/divergent"
divergent_run="$("$LEDGER" init \
  --root "$divergent_root" \
  --mode divergent-analysis \
  --target docs/plan.md \
  --objective "Explore target-adaptive next directions" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Adaptive divergent")"

adaptive_missing_rationale="$tmpdir/adaptive-missing-rationale.json"
cat >"$adaptive_missing_rationale" <<'JSON'
[
  {"slot": "D1", "lens": "Regime Detection", "question": "Which market regimes matter?"},
  {"slot": "D2", "lens": "Data Leakage Risk", "question": "Where can leakage enter?"},
  {"slot": "D3", "lens": "Execution Reality", "question": "Can this trade after costs?"},
  {"slot": "D4", "lens": "Research Throughput", "question": "What speeds up iteration?"},
  {"slot": "D5", "lens": "Overfitting Risk", "question": "Where is the strategy overfit?"},
  {"slot": "D6", "lens": "Portfolio Fit", "question": "Does this diversify existing bets?"}
]
JSON

if "$LEDGER" prepare-round --run-dir "$divergent_run" --round 1 --assignments "$adaptive_missing_rationale" >/dev/null 2>&1; then
  echo "divergent round 1 should require why_material and expected_new_information" >&2
  exit 1
fi

divergent_good="$tmpdir/divergent-good.json"
cat >"$divergent_good" <<'JSON'
[
  {"slot": "D1", "lens": "Regime Detection", "question": "Which market regimes matter?", "why_material": "Regime selection can change the research path.", "expected_new_information": "Regimes worth isolating before model work."},
  {"slot": "D2", "lens": "Data Leakage Risk", "question": "Where can leakage enter?", "why_material": "Leakage can invalidate apparent alpha.", "expected_new_information": "Leakage paths and controls needed before research continues."},
  {"slot": "D3", "lens": "Execution Reality", "question": "Can this trade after costs?", "why_material": "Backtests can fail after fees, slippage, latency, and capacity.", "expected_new_information": "Execution constraints that change feasibility."},
  {"slot": "D4", "lens": "Research Throughput", "question": "What speeds up iteration?", "why_material": "The next direction depends on how quickly evidence can be produced.", "expected_new_information": "Bottlenecks in data, compute, labeling, and review loops."},
  {"slot": "D5", "lens": "Overfitting Risk", "question": "Where is the strategy overfit?", "why_material": "Overfitting determines whether more search is useful.", "expected_new_information": "Falsification tests for fragile alpha."},
  {"slot": "D6", "lens": "Portfolio Fit", "question": "Does this diversify existing bets?", "why_material": "A weaker standalone strategy can still be valuable if diversifying.", "expected_new_information": "Correlation and allocation questions for the next step."}
]
JSON

"$LEDGER" prepare-round \
  --run-dir "$divergent_run" \
  --round 1 \
  --assignments "$divergent_good" >/dev/null

for slot in D1 D2 D3 D4 D5 D6; do
  "$LEDGER" plan-dispatch --run-dir "$divergent_run" --round 1 --slot "$slot" >/dev/null
  "$LEDGER" record-spawn --run-dir "$divergent_run" --round 1 --slot "$slot" \
    --agent-id "agent-$slot" --status spawned >/dev/null
  "$LEDGER" record-result --run-dir "$divergent_run" --round 1 --slot "$slot" \
    --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close --run-dir "$divergent_run" --round 1 --slot "$slot" \
    --status closed >/dev/null
done
divergent_missing_alignment="$tmpdir/divergent-missing-objective-alignment.json"
cat >"$divergent_missing_alignment" <<'JSON'
{
  "convergence": ["The adaptive lenses produced a shared conclusion."],
  "action_list": ["Apply the divergent synthesis."],
  "expected_value_of_another_round": "No additional round is needed.",
  "cross_review_targets": [],
  "cross_review_outcomes": []
}
JSON
if "$LEDGER" record-synthesis --run-dir "$divergent_run" --round 1 \
  --synthesis "$divergent_missing_alignment" >/dev/null 2>&1; then
  echo "divergent-analysis first synthesis should require objective_alignment" >&2
  exit 1
fi

create_completed_cross_review_round

needs_cross_review="$tmpdir/needs-cross-review.json"
cat >"$needs_cross_review" <<'JSON'
{
  "convergence": ["The base plan is useful."],
  "disagreement": ["A5 wants a guardrail while A2 worries about complexity."],
  "critical_disagreements": ["Whether the guardrail should be mandatory."],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Cross-review the guardrail before accepting it."],
  "cross_review_gate_status": "needs_cross_review",
  "cross_review_targets": [
    {"target_id": "cr-guardrail", "source_slot": "A5", "claim": "Add a mandatory guardrail before every run.", "why_decision_critical": "It changes every user workflow.", "disposition": "pending"}
  ],
  "cross_review_outcomes": [],
  "expected_value_of_another_round": "High because the guardrail decision can change implementation scope.",
  "next_round_decision": "continue_round_2",
  "stop_reason": "",
  "next_round_question": "Cross-review cr-guardrail."
}
JSON

with_objective_alignment \
  "$needs_cross_review" \
  "needs_revision" \
  "The cross-review target must be resolved before the objective is satisfied." \
  '["Resolve the guardrail decision."]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 1 --synthesis "$needs_cross_review" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision stop --summary "Stop with pending target" >/dev/null 2>&1; then
  echo "finalize-round should reject stop while cross_review_gate_status needs_cross_review" >&2
  exit 1
fi

"$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision continue_round_2 --summary "Cross-review cr-guardrail." >/dev/null

create_completed_cross_review_round
pending_but_clear="$tmpdir/pending-but-clear.json"
cat >"$pending_but_clear" <<'JSON'
{
  "convergence": ["The base plan is useful."],
  "disagreement": ["A5 proposes a guardrail that changes scope."],
  "critical_disagreements": ["Whether the guardrail is required."],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Do not finalize before the guardrail is cross-reviewed."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [
    {"target_id": "cr-guardrail", "source_slot": "A5", "claim": "Add a mandatory guardrail before every run.", "why_decision_critical": "It changes every user workflow.", "disposition": "pending"}
  ],
  "cross_review_outcomes": [],
  "expected_value_of_another_round": "High because the guardrail decision changes implementation scope.",
  "next_round_decision": "stop",
  "stop_reason": "",
  "next_round_question": ""
}
JSON

with_objective_alignment \
  "$pending_but_clear" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 1 --synthesis "$pending_but_clear" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision stop --summary "Stop with pending target despite clear gate" >/dev/null 2>&1; then
  echo "finalize-round should reject stop while current synthesis still has pending cross-review targets" >&2
  exit 1
fi

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision continue_round_2 --summary "Continue with pending target despite clear gate" >/dev/null 2>&1; then
  echo "finalize-round should reject continue_round_2 while current synthesis has pending cross-review targets and clear gate" >&2
  exit 1
fi

if "$LEDGER" prepare-round --run-dir "$cross_run" --round 2 --assignments "$six" >/dev/null 2>&1; then
  echo "generic round-2 preparation should not be possible after invalid cross-review finalize decision" >&2
  exit 1
fi

create_completed_cross_review_round
needs_cross_review_multi="$tmpdir/needs-cross-review-multi-targets.json"
cat >"$needs_cross_review_multi" <<'JSON'
{
  "convergence": ["Both suggestions are useful."],
  "disagreement": ["The team disagrees on safety versus speed."],
  "critical_disagreements": ["Guardrail scope changes both rollout risk and compliance."],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": [
    "Cross-review both claims before execution.",
    "Prioritize evidence that closes the highest-risk claim."
  ],
  "cross_review_gate_status": "needs_cross_review",
  "cross_review_targets": [
    {
      "target_id": "cr-guardrail",
      "source_slot": "A5",
      "claim": "Add a mandatory guardrail before every run.",
      "why_decision_critical": "Guardrails are non-negotiable in regulated environments.",
      "disposition": "pending"
    },
    {
      "target_id": "cr-rollback-plan",
      "source_slot": "A2",
      "claim": "Require explicit rollback plan before deployment.",
      "why_decision_critical": "Rollback coverage can prevent user-facing incidents.",
      "disposition": "pending"
    }
  ],
  "cross_review_outcomes": [],
  "expected_value_of_another_round": "High because both claims alter risk posture.",
  "next_round_decision": "continue_round_2",
  "stop_reason": "",
  "next_round_question": "Cross-review both claims."
}
JSON

with_objective_alignment \
  "$needs_cross_review_multi" \
  "needs_revision" \
  "The cross-review targets must be resolved before the objective is satisfied." \
  '["Resolve the guardrail and rollback decisions."]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 1 --synthesis "$needs_cross_review_multi" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision stop --summary "Stop while pending targets remain." >/dev/null 2>&1; then
  echo "finalize-round should reject stop while cross_review_gate_status needs_cross_review" >&2
  exit 1
fi

"$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision continue_round_2 --summary "Cross-review both claims." >/dev/null

round2_partial_targets="$tmpdir/round2-partial-targets.json"
cat >"$round2_partial_targets" <<'JSON'
[
  {"slot": "C1", "lens": "Occam's Razor", "question": "Is the guardrail overbuilt?", "target_id": "cr-guardrail"},
  {"slot": "C2", "lens": "Expected Cost Optimality", "question": "Is the cost worth it?", "target_id": "cr-guardrail"},
  {"slot": "C3", "lens": "Execution Friction", "question": "Will users follow it?", "target_id": "cr-guardrail"},
  {"slot": "C4", "lens": "Adversarial Review", "question": "What fails without it?", "target_id": "cr-guardrail"},
  {"slot": "C5", "lens": "Bounded Bayesian", "question": "What evidence changes confidence?", "target_id": "cr-guardrail"},
  {"slot": "C6", "lens": "Scope Control", "question": "What smaller version preserves benefit?", "target_id": "cr-guardrail"}
]
JSON

if "$LEDGER" prepare-round --run-dir "$cross_run" --round 2 --assignments "$round2_partial_targets" >/dev/null 2>&1; then
  echo "prepare-round should reject partial coverage of pending cross-review target ids" >&2
  exit 1
fi

create_completed_cross_review_round
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 1 --synthesis "$needs_cross_review" >/dev/null
"$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision continue_round_2 --summary "Cross-review cr-guardrail." >/dev/null

round2_wrong_slots="$tmpdir/round2-wrong-slots.json"
cat >"$round2_wrong_slots" <<'JSON'
[
  {"slot": "X1", "lens": "Occam's Razor", "question": "Is the guardrail overbuilt?", "target_id": "cr-guardrail"},
  {"slot": "X2", "lens": "Expected Cost Optimality", "question": "Is the cost worth it?", "target_id": "cr-guardrail"},
  {"slot": "X3", "lens": "Execution Friction", "question": "Will users follow it?", "target_id": "cr-guardrail"},
  {"slot": "X4", "lens": "Adversarial Review", "question": "What fails without it?", "target_id": "cr-guardrail"},
  {"slot": "X5", "lens": "Bounded Bayesian", "question": "What evidence changes confidence?", "target_id": "cr-guardrail"},
  {"slot": "X6", "lens": "Scope Control", "question": "What smaller version works?", "target_id": "cr-guardrail"}
]
JSON

if "$LEDGER" prepare-round --run-dir "$cross_run" --round 2 --assignments "$round2_wrong_slots" >/dev/null 2>&1; then
  echo "round 2 targeted cross-review should require C1-C6 slots when prior pending targets exist" >&2
  exit 1
fi

round2_unknown_target="$tmpdir/round2-unknown-target.json"
cat >"$round2_unknown_target" <<'JSON'
[
  {"slot": "C1", "lens": "Occam's Razor", "question": "Is the guardrail overbuilt?", "target_id": "cr-other"},
  {"slot": "C2", "lens": "Expected Cost Optimality", "question": "Is the cost worth it?", "target_id": "cr-other"},
  {"slot": "C3", "lens": "Execution Friction", "question": "Will users follow it?", "target_id": "cr-other"},
  {"slot": "C4", "lens": "Adversarial Review", "question": "What fails without it?", "target_id": "cr-other"},
  {"slot": "C5", "lens": "Bounded Bayesian", "question": "What evidence changes confidence?", "target_id": "cr-other"},
  {"slot": "C6", "lens": "Scope Control", "question": "What smaller version works?", "target_id": "cr-other"}
]
JSON

if "$LEDGER" prepare-round --run-dir "$cross_run" --round 2 --assignments "$round2_unknown_target" >/dev/null 2>&1; then
  echo "round 2 should reject unknown cross-review target ids" >&2
  exit 1
fi

round2_good="$tmpdir/round2-good.json"
cat >"$round2_good" <<'JSON'
[
  {"slot": "C1", "lens": "Occam's Razor", "question": "Is the guardrail overbuilt?", "target_id": "cr-guardrail"},
  {"slot": "C2", "lens": "Expected Cost Optimality", "question": "Is the cost worth it?", "target_id": "cr-guardrail"},
  {"slot": "C3", "lens": "Execution Friction", "question": "Will users follow it?", "target_id": "cr-guardrail"},
  {"slot": "C4", "lens": "Adversarial Review", "question": "What fails without it?", "target_id": "cr-guardrail"},
  {"slot": "C5", "lens": "Bounded Bayesian", "question": "What evidence changes confidence?", "target_id": "cr-guardrail"},
  {"slot": "C6", "lens": "Scope Control", "question": "What smaller version preserves benefit?", "target_id": "cr-guardrail"}
]
JSON

"$LEDGER" prepare-round --run-dir "$cross_run" --round 2 --assignments "$round2_good" >/dev/null

for slot in C1 C2 C3 C4 C5 C6; do
  "$LEDGER" record-spawn --run-dir "$cross_run" --round 2 --slot "$slot" --agent-id "agent-$slot" --status spawned >/dev/null
  "$LEDGER" record-result --run-dir "$cross_run" --round 2 --slot "$slot" --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close --run-dir "$cross_run" --round 2 --slot "$slot" --status closed >/dev/null
done

unresolved_outcome="$tmpdir/unresolved-outcome.json"
cat >"$unresolved_outcome" <<'JSON'
{
  "convergence": ["The guardrail remains disputed."],
  "disagreement": ["Cost and risk remain unresolved."],
  "critical_disagreements": ["The guardrail decision still changes scope."],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Ask user or gather evidence before implementation."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [],
  "cross_review_outcomes": [
    {"target_id": "cr-guardrail", "status": "unresolved", "rationale": "Reviewers still disagree on mandatory scope."}
  ],
  "expected_value_of_another_round": "Low without new evidence.",
  "next_round_decision": "stop",
  "stop_reason": "Attempted stop with unresolved outcome.",
  "next_round_question": ""
}
JSON

with_objective_alignment \
  "$unresolved_outcome" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 2 --synthesis "$unresolved_outcome" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 2 --decision stop --summary "Stop unresolved" >/dev/null 2>&1; then
  echo "finalize-round should reject stop with unresolved cross-review outcome" >&2
  exit 1
fi

missing_outcome="$tmpdir/missing-outcome.json"
cat >"$missing_outcome" <<'JSON'
{
  "convergence": ["A lighter-weight safeguard is still possible."],
  "disagreement": ["The mandatory guardrail is still debated."],
  "critical_disagreements": ["The scope effect remains important."],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Gather one more evidence point before implementation."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [],
  "cross_review_outcomes": [],
  "expected_value_of_another_round": "Low now that the team can escalate directly.",
  "next_round_decision": "stop",
  "stop_reason": "",
  "next_round_question": ""
}
JSON

with_objective_alignment \
  "$missing_outcome" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 2 --synthesis "$missing_outcome" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 2 --decision stop --summary "Stop with missing outcome" >/dev/null 2>&1; then
  echo "finalize-round should reject stop when prior pending target_ids have no outcomes" >&2
  exit 1
fi

extra_outcome="$tmpdir/extra-outcome.json"
cat >"$extra_outcome" <<'JSON'
{
  "convergence": ["A lighter-weight safeguard is enough."],
  "disagreement": [],
  "critical_disagreements": [],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Implement the checklist version."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [],
  "cross_review_outcomes": [
    {"target_id": "cr-guardrail", "status": "modified", "rationale": "Use a lightweight checklist instead of a mandatory guardrail."},
    {"target_id": "cr-extra", "status": "accepted", "rationale": "Unexpected extra target should not be accepted here."}
  ],
  "expected_value_of_another_round": "Low once the mandatory version is rejected.",
  "next_round_decision": "stop",
  "stop_reason": "",
  "next_round_question": ""
}
JSON

with_objective_alignment \
  "$extra_outcome" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 2 --synthesis "$extra_outcome" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 2 --decision stop --summary "Stop with extra outcome target" >/dev/null 2>&1; then
  echo "finalize-round should reject extra cross-review outcome target ids" >&2
  exit 1
fi

resolved_outcome="$tmpdir/resolved-outcome.json"
cat >"$resolved_outcome" <<'JSON'
{
  "convergence": ["A lighter-weight safeguard is enough."],
  "disagreement": [],
  "critical_disagreements": [],
  "cannot_verify": [],
  "high_impact_low_evidence": [],
  "action_list": ["Implement the checklist version."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [
    {"target_id": "cr-guardrail", "source_slot": "A5", "claim": "Add a mandatory guardrail before every run.", "why_decision_critical": "It changes every user workflow.", "disposition": "downgraded_non_decision_critical"}
  ],
  "cross_review_outcomes": [
    {"target_id": "cr-guardrail", "status": "modified", "rationale": "Use a lightweight checklist instead of a mandatory guardrail."}
  ],
  "expected_value_of_another_round": "Low once the mandatory version is rejected.",
  "next_round_decision": "stop",
  "stop_reason": "",
  "next_round_question": ""
}
JSON

with_objective_alignment \
  "$resolved_outcome" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 2 --synthesis "$resolved_outcome" >/dev/null
"$LEDGER" finalize-round --run-dir "$cross_run" --round 2 --decision stop --summary "Stop with modified outcome" >/dev/null

if ! grep -q "Cross Review Gate Status" "$cross_run/round-02.md"; then
  echo "round markdown should render cross review gate status" >&2
  exit 1
fi
if ! grep -q "Target cr-guardrail" "$cross_run/round-02.md"; then
  echo "round markdown should render cross review targets with identifiers" >&2
  exit 1
fi
if ! grep -q "Outcome for cr-guardrail" "$cross_run/round-02.md"; then
  echo "round markdown should render cross review outcomes with distinct context" >&2
  exit 1
fi

create_completed_cross_review_round
externalized_target_clear_gate="$tmpdir/externalized-target-clear-gate.json"
cat >"$externalized_target_clear_gate" <<'JSON'
{
  "convergence": ["External verification is required before acting."],
  "disagreement": ["The team cannot settle the guardrail claim internally."],
  "critical_disagreements": ["The claim remains decision-critical without external evidence."],
  "cannot_verify": ["Production data needed to validate the guardrail claim."],
  "high_impact_low_evidence": ["The guardrail could change every user workflow."],
  "action_list": ["Escalate the guardrail claim to external verification."],
  "cross_review_gate_status": "clear",
  "cross_review_targets": [
    {"target_id": "cr-guardrail", "source_slot": "A5", "claim": "Add a mandatory guardrail before every run.", "why_decision_critical": "It changes every user workflow.", "disposition": "external_verification"}
  ],
  "cross_review_outcomes": [],
  "expected_value_of_another_round": "Low without external evidence.",
  "next_round_decision": "stop",
  "stop_reason": "",
  "next_round_question": ""
}
JSON

with_objective_alignment \
  "$externalized_target_clear_gate" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]'
"$LEDGER" record-synthesis --run-dir "$cross_run" --round 1 --synthesis "$externalized_target_clear_gate" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision stop --summary "Stop with externalized target but clear gate" >/dev/null 2>&1; then
  echo "finalize-round should require external_verification gate status when stopping with externalized cross-review targets" >&2
  exit 1
fi

duplicate_lens="$tmpdir/adaptive-duplicate-lens.json"
python3 - "$divergent_good" "$duplicate_lens" <<'PY'
import json
import sys
from pathlib import Path

src, dst = sys.argv[1], sys.argv[2]
payload = json.load(open(src, encoding="utf-8"))
payload[1]["lens"] = payload[0]["lens"]
json.dump(payload, open(dst, "w", encoding="utf-8"), indent=2)
PY

duplicate_run="$(init_legacy \
  --root "$tmpdir/.superpowers/duplicate-lens" \
  --mode divergent-analysis \
  --target docs/plan.md \
  --objective "Reject duplicated lenses" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Duplicate lens")"

if "$LEDGER" prepare-round --run-dir "$duplicate_run" --round 1 --assignments "$duplicate_lens" >/dev/null 2>&1; then
  echo "divergent round 1 should reject duplicate lens labels" >&2
  exit 1
fi

if init_legacy \
  --root "$tmpdir/.superpowers/blank-objective" \
  --mode review \
  --target docs/plan.md \
  --objective "   " \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Blank objective" >/dev/null 2>&1; then
  echo "init should reject blank objectives" >&2
  exit 1
fi

create_completed_objective_round() {
  objective_run="$(init_legacy \
    --root "$tmpdir/.superpowers/objective-alignment" \
    --mode review \
    --target docs/plan.md \
    --objective "Decide whether the implementation plan is ready" \
    --spawn-tool spawn \
    --wait-tool wait \
    --close-tool close \
    --title "Objective alignment")"

  "$LEDGER" prepare-round --run-dir "$objective_run" --round 1 --assignments "$six" >/dev/null
  for slot in A1 A2 A3 A4 A5 A6; do
    "$LEDGER" record-spawn --run-dir "$objective_run" --round 1 --slot "$slot" --agent-id "agent-$slot" --status spawned >/dev/null
    "$LEDGER" record-result --run-dir "$objective_run" --round 1 --slot "$slot" --status completed --summary "$slot result" >/dev/null
    "$LEDGER" record-close --run-dir "$objective_run" --round 1 --slot "$slot" --status closed >/dev/null
  done
}

write_objective_synthesis() {
  local path="$1"
  local status="$2"
  local rationale="$3"
  local unmet_requirements="$4"
  local decision="$5"
  python3 - "$path" "$status" "$rationale" "$unmet_requirements" "$decision" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
status = sys.argv[2]
rationale = sys.argv[3]
unmet_requirements = json.loads(sys.argv[4])
decision = sys.argv[5]
payload = {
    "convergence": ["The synthesis has a shared conclusion."],
    "disagreement": [],
    "critical_disagreements": [],
    "cannot_verify": [],
    "high_impact_low_evidence": [],
    "action_list": ["Apply the synthesis result."],
    "expected_value_of_another_round": "Another round is only useful for unresolved requirements.",
    "next_round_decision": decision,
    "stop_reason": "The objective is satisfied." if decision == "stop" else "",
    "next_round_question": "Resolve the unmet requirement." if decision != "stop" else "",
    "objective_alignment": {
        "status": status,
        "rationale": rationale,
        "unmet_requirements": unmet_requirements,
    },
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

create_completed_objective_round
aligned_stop="$tmpdir/aligned-stop.json"
write_objective_synthesis \
  "$aligned_stop" \
  "aligned" \
  "The synthesis answers the original objective and retains the stated constraints." \
  '[]' \
  "stop"
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 --synthesis "$aligned_stop" >/dev/null
"$LEDGER" finalize-round --run-dir "$objective_run" --round 1 --decision stop --summary "Objective is satisfied." >/dev/null
if ! grep -q "### Objective Alignment" "$objective_run/round-01.md"; then
  echo "round markdown should render objective alignment" >&2
  exit 1
fi
if ! grep -q "Status: aligned" "$objective_run/round-01.md"; then
  echo "round markdown should render objective alignment status" >&2
  exit 1
fi

create_completed_objective_round
missing_alignment="$tmpdir/missing-objective-alignment.json"
python3 - "$aligned_stop" "$missing_alignment" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload.pop("objective_alignment")
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
if "$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 --synthesis "$missing_alignment" >/dev/null 2>&1; then
  echo "record-synthesis should require objective_alignment" >&2
  exit 1
fi

for invalid_case in invalid-status blank-rationale malformed-unmet unexpected-field aligned-with-unmet needs-revision-without-unmet; do
  create_completed_objective_round
  invalid_synthesis="$tmpdir/$invalid_case.json"
  case "$invalid_case" in
    invalid-status)
      write_objective_synthesis "$invalid_synthesis" "uncertain" "The synthesis is structurally valid." '[]' "stop"
      ;;
    blank-rationale)
      write_objective_synthesis "$invalid_synthesis" "aligned" "   " '[]' "stop"
      ;;
    malformed-unmet)
      write_objective_synthesis "$invalid_synthesis" "needs_revision" "An important constraint remains unresolved." '["", 3]' "ask_user"
      ;;
    unexpected-field)
      write_objective_synthesis "$invalid_synthesis" "aligned" "The synthesis is structurally valid." '[]' "stop"
      python3 - "$invalid_synthesis" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["objective_alignment"]["extra"] = "not allowed"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
      ;;
    aligned-with-unmet)
      write_objective_synthesis "$invalid_synthesis" "aligned" "The synthesis is structurally valid." '["Confirm deployment owner."]' "stop"
      ;;
    needs-revision-without-unmet)
      write_objective_synthesis "$invalid_synthesis" "needs_revision" "An important constraint remains unresolved." '[]' "ask_user"
      ;;
  esac
  if "$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 --synthesis "$invalid_synthesis" >/dev/null 2>&1; then
    echo "record-synthesis should reject $invalid_case objective alignment" >&2
    exit 1
  fi
done

create_completed_objective_round
needs_revision_stop="$tmpdir/needs-revision-stop.json"
write_objective_synthesis \
  "$needs_revision_stop" \
  "needs_revision" \
  "A user decision is needed before the recommendation can satisfy the objective." \
  '["Choose the deployment owner."]' \
  "stop"
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 --synthesis "$needs_revision_stop" >/dev/null
"$LEDGER" finalize-round --run-dir "$objective_run" --round 1 --decision stop \
  --summary "The unmet requirement is the final review finding." >/dev/null

create_completed_objective_round
needs_revision_ask_user="$tmpdir/needs-revision-ask-user.json"
objective_continue="$tmpdir/objective-continue.json"
write_objective_synthesis \
  "$objective_continue" \
  "needs_revision" \
  "A follow-up round must resolve the deployment owner before the objective is satisfied." \
  '["Choose the deployment owner."]' \
  "continue_round_2"
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 --synthesis "$objective_continue" >/dev/null
"$LEDGER" finalize-round --run-dir "$objective_run" --round 1 --decision continue_round_2 --summary "Resolve the deployment owner." >/dev/null
"$LEDGER" prepare-round --run-dir "$objective_run" --round 2 --assignments "$six" >/dev/null
for slot in A1 A2 A3 A4 A5 A6; do
  "$LEDGER" record-spawn --run-dir "$objective_run" --round 2 --slot "$slot" --agent-id "agent-$slot-round-2" --status spawned >/dev/null
  "$LEDGER" record-result --run-dir "$objective_run" --round 2 --slot "$slot" --status completed --summary "$slot round two result" >/dev/null
  "$LEDGER" record-close --run-dir "$objective_run" --round 2 --slot "$slot" --status closed >/dev/null
done
write_objective_synthesis \
  "$needs_revision_ask_user" \
  "needs_revision" \
  "The user must choose a deployment owner before the objective is satisfied." \
  '["Choose the deployment owner."]' \
  "ask_user"
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 2 --synthesis "$needs_revision_ask_user" >/dev/null
"$LEDGER" finalize-round --run-dir "$objective_run" --round 2 --decision ask_user --summary "Choose a deployment owner." >/dev/null

create_completed_objective_round
weak_rationale="$tmpdir/weak-rationale.json"
write_objective_synthesis "$weak_rationale" "aligned" "Fine." '[]' "stop"
"$LEDGER" record-synthesis --run-dir "$objective_run" --round 1 --synthesis "$weak_rationale" >/dev/null
"$LEDGER" finalize-round --run-dir "$objective_run" --round 1 --decision stop --summary "Structural validation accepts weak rationale." >/dev/null

engineering_review_run="$("$LEDGER" init \
  --root "$tmpdir/.superpowers/engineering-review" \
  --mode review \
  --target docs/plan.md \
  --target-overlay engineering \
  --objective "Review the engineering implementation plan" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Engineering review")"

python3 - "$engineering_review_run/state.json" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if state.get("target_overlay") != "engineering":
    raise SystemExit("init must persist engineering target_overlay in state.json")
PY

engineering_review_assignments="$tmpdir/engineering-review.json"
python3 - "$six" "$engineering_review_assignments" <<'PY'
import json
import sys
from pathlib import Path

checks = {
    "A1": ["functional-requirements", "non-functional-requirements", "acceptance-criteria", "compatibility-and-platform-constraints"],
    "A2": ["simplest-sufficient-mechanism", "architecture-and-ownership-boundaries", "interfaces-data-flow-and-state", "dependency-necessity"],
    "A3": ["prototype-test-and-benchmark-evidence", "technical-assumptions", "missing-evidence", "falsification-conditions"],
    "A4": ["build-buy-and-alternative-architecture", "implementation-and-operating-cost", "migration-and-switching-cost", "reversibility-and-opportunity-cost"],
    "A5": ["concurrency-and-data-integrity", "security-and-abuse", "dependency-and-capacity-failure", "degradation-recovery-and-rollback"],
    "A6": ["implementation-sequence-and-ownership", "test-strategy-and-observability", "deployment-and-migration", "maintenance-and-handoff"],
}
assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for assignment in assignments:
    assignment["overlay_checks"] = checks[assignment["slot"]]
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

"$LEDGER" prepare-round --run-dir "$engineering_review_run" --round 1 --assignments "$engineering_review_assignments" >/dev/null

engineering_missing_check="$tmpdir/engineering-missing-check.json"
python3 - "$engineering_review_assignments" "$engineering_missing_check" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments[0]["overlay_checks"] = assignments[0]["overlay_checks"][:-1]
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

engineering_invalid_run="$("$LEDGER" init \
  --root "$tmpdir/.superpowers/engineering-invalid" \
  --mode review \
  --target docs/plan.md \
  --target-overlay engineering \
  --objective "Reject incomplete engineering overlay" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Incomplete engineering overlay")"
if "$LEDGER" prepare-round --run-dir "$engineering_invalid_run" --round 1 --assignments "$engineering_missing_check" >/dev/null 2>&1; then
  echo "engineering review must require each slot's exact overlay checks" >&2
  exit 1
fi

divergent_engineering_run="$("$LEDGER" init \
  --root "$tmpdir/.superpowers/divergent-engineering" \
  --mode divergent-analysis \
  --target docs/architecture.md \
  --target-overlay engineering \
  --objective "Explore implementation options" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Engineering divergent analysis")"

divergent_engineering_assignments="$tmpdir/divergent-engineering.json"
python3 - "$divergent_good" "$divergent_engineering_assignments" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments[2]["overlay_role"] = "engineering-feasibility"
assignments[2]["overlay_checks"] = [
    "simplest-sufficient-mechanism",
    "implementation-feasibility",
    "testability-and-observability",
    "failure-recovery-and-reversibility",
    "maintenance-portability-and-handoff",
]
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

"$LEDGER" prepare-round --run-dir "$divergent_engineering_run" --round 1 --assignments "$divergent_engineering_assignments" >/dev/null

divergent_wrong_slots="$tmpdir/divergent-wrong-slots.json"
python3 - "$divergent_engineering_assignments" "$divergent_wrong_slots" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for index, assignment in enumerate(assignments, start=1):
    assignment["slot"] = f"X{index}"
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

divergent_wrong_slot_run="$("$LEDGER" init \
  --root "$tmpdir/.superpowers/divergent-wrong-slots" \
  --mode divergent-analysis \
  --target docs/architecture.md \
  --target-overlay engineering \
  --objective "Reject non-D divergent slots" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Wrong divergent slots")"
if "$LEDGER" prepare-round --run-dir "$divergent_wrong_slot_run" --round 1 --assignments "$divergent_wrong_slots" >/dev/null 2>&1; then
  echo "divergent round 1 must require exact D1-D6 slots, including engineering-feasibility on D3" >&2
  exit 1
fi

divergent_extra_engineering="$tmpdir/divergent-extra-engineering.json"
python3 - "$divergent_engineering_assignments" "$divergent_extra_engineering" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments[3]["overlay_role"] = "engineering-feasibility"
assignments[3]["overlay_checks"] = assignments[2]["overlay_checks"]
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

divergent_invalid_run="$("$LEDGER" init \
  --root "$tmpdir/.superpowers/divergent-invalid" \
  --mode divergent-analysis \
  --target docs/architecture.md \
  --target-overlay engineering \
  --objective "Reject duplicate engineering angle" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Duplicate engineering angle")"
if "$LEDGER" prepare-round --run-dir "$divergent_invalid_run" --round 1 --assignments "$divergent_extra_engineering" >/dev/null 2>&1; then
  echo "engineering divergent analysis must require exactly one engineering-feasibility role" >&2
  exit 1
fi

non_engineering_overlay_run="$("$LEDGER" init \
  --root "$tmpdir/.superpowers/no-overlay" \
  --mode divergent-analysis \
  --target docs/market.md \
  --objective "Explore market options" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "No engineering overlay")"
if "$LEDGER" prepare-round --run-dir "$non_engineering_overlay_run" --round 1 --assignments "$divergent_engineering_assignments" >/dev/null 2>&1; then
  echo "runs without an engineering overlay must reject overlay fields" >&2
  exit 1
fi

echo "orchestrating-multi-agent-analysis ledger helper looks good"
