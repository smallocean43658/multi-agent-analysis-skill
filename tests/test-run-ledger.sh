#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="$REPO_ROOT/scripts/run-ledger"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

root="$tmpdir/.superpowers/multi-agent-analysis"

run_dir="$("$LEDGER" init \
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

if "$LEDGER" init \
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

invalid_status_run="$("$LEDGER" init \
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

abnormal_run="$("$LEDGER" init \
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

blocked_run="$("$LEDGER" init \
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

"$LEDGER" record-spawn \
  --run-dir "$blocked_run" \
  --round 1 \
  --slot A1 \
  --agent-id agent-a1 \
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

open_blocked_run="$("$LEDGER" init \
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

no_activity_blocked_run="$("$LEDGER" init \
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

failed_result_run="$("$LEDGER" init \
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

duplicate_run="$("$LEDGER" init \
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
  {"slot": "B1", "lens": "Follow-up 1", "question": "What needs follow-up 1?"},
  {"slot": "B2", "lens": "Follow-up 2", "question": "What needs follow-up 2?"},
  {"slot": "B3", "lens": "Follow-up 3", "question": "What needs follow-up 3?"},
  {"slot": "B4", "lens": "Follow-up 4", "question": "What needs follow-up 4?"},
  {"slot": "B5", "lens": "Follow-up 5", "question": "What needs follow-up 5?"},
  {"slot": "B6", "lens": "Follow-up 6", "question": "What needs follow-up 6?"}
]
JSON

"$LEDGER" prepare-round \
  --run-dir "$run_dir" \
  --round 2 \
  --assignments "$round2" >/dev/null

for slot in B1 B2 B3 B4 B5 B6; do
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
  --objective "Find non-obvious decision angles" \
  --spawn-tool spawn_agent \
  --wait-tool wait_agent \
  --close-tool close_agent \
  --title "Divergent plan analysis")"

divergent_bad="$tmpdir/divergent-bad.json"
cat >"$divergent_bad" <<'JSON'
[
  {"slot": "S1", "lens": "User Behavior & Adoption", "question": "Who adopts?"},
  {"slot": "S2", "lens": "Workflow & Operational Reality", "question": "What workflow changes?"},
  {"slot": "S3", "lens": "System Mechanics & Dependencies", "question": "What mechanisms hold?"},
  {"slot": "S4", "lens": "Failure, Abuse & Recovery", "question": "How can this fail?"},
  {"slot": "S5", "lens": "Economics, Time & Opportunity Cost", "question": "Is this worth it?"},
  {"slot": "S6", "lens": "Wildcard Non-Obvious Angle", "question": "What else matters?"}
]
JSON

if "$LEDGER" prepare-round --run-dir "$divergent_run" --round 1 --assignments "$divergent_bad" >/dev/null 2>&1; then
  echo "divergent S6 should require wildcard metadata" >&2
  exit 1
fi

divergent_good="$tmpdir/divergent-good.json"
python3 - "$divergent_bad" "$divergent_good" <<'PY'
import json
import sys
from pathlib import Path

assignments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assignments[5]["wildcard_family"] = "Measurement & Falsifiability"
assignments[5]["why_material"] = "The decision needs falsifiable success criteria."
assignments[5]["why_not_redundant"] = "No fixed slot directly tests measurement quality."
Path(sys.argv[2]).write_text(json.dumps(assignments, indent=2) + "\n", encoding="utf-8")
PY

"$LEDGER" prepare-round \
  --run-dir "$divergent_run" \
  --round 1 \
  --assignments "$divergent_good" >/dev/null

echo "orchestrating-multi-agent-analysis ledger helper looks good"
