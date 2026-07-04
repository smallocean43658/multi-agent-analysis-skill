# Adaptive Divergent Analysis And Cross-Review Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make multi-agent divergent analysis target-adaptive and make decision-critical cross-review claims auditable without turning the ledger helper into a broad policy engine.

**Architecture:** Keep `review` mode's fixed first-round six lenses. Make `divergent-analysis` choose six target-specific lenses instead of a fixed taxonomy, while preserving explicit multi-agent wording as the trigger precondition. Let the main agent decide which claims are decision-critical; the helper only enforces mechanical integrity for declared cross-review targets, target coverage, outcome status, and rendered records.

**Tech Stack:** Markdown skill instructions, Python 3.10+ helper script, Bash 4+ smoke tests, JSON prompt contract corpus.

## Global Constraints

- Do not change `review` round-one lenses: First Principles, Occam's Razor, Bounded Bayesian, Expected Cost Optimality, Adversarial Review, Execution Friction.
- Do not trigger this skill from ordinary `分析` / `analysis` wording; explicit multi-agent, multi-subagent, or six-agent wording remains mandatory.
- Route explicit generic multi-agent analysis wording such as `多子代理分析`, `多代理分析`, `六代理分析`, and `multi-agent analysis` to `divergent-analysis` unless the user says review/evaluate/stress-test an existing artifact.
- Preserve exactly six subagents per valid round.
- Keep helper enforcement narrow: lifecycle integrity, assignment shape, declared cross-review target integrity, and rendered ledger visibility.
- Do not encode broad analytical judgment into `scripts/run-ledger`; the main agent owns claim importance, lens choice, synthesis, and whether a claim is downgraded or externalized.
- Do not prescribe direct push to `main` in this plan. Commit and push only when the user asks after verification.

---

## Review Feedback Incorporated

- Accepted: remove the product-centric fixed divergent taxonomy.
- Accepted: keep ordinary analysis requests as non-triggers.
- Accepted: use claim-level `target_id` for cross-review targets, assignments, and outcomes.
- Accepted: render new cross-review fields into `round-N.md`.
- Accepted: add worker prompt smoke coverage if the prompt becomes contractual.
- Accepted: remove the undefined `$cross_round2_run` variable from the plan.
- Accepted: avoid exact review-lens bans as helper logic.
- Accepted: avoid multiple intermediate commits and direct push instructions.
- Rejected: making cross-review purely advisory. The user explicitly wants a real gate; this plan implements a narrow mechanical gate around claims the main agent has already declared decision-critical.

---

## File Structure

- Modify `SKILL.md`: trigger boundary, adaptive divergent mode, cross-review gate, continuation/stop rules, slot conventions, validation command list.
- Modify `round-subagent-prompt.md`: accepted slot families, adaptive divergent assignment fields, targeted cross-review output contract.
- Modify `scripts/run-ledger`: adaptive divergent assignment shape, cross-review target/outcome validation, round-two target coverage, markdown rendering.
- Modify `test-prompts.json`: prompt-level trigger and behavior cases.
- Modify `tests/test-prompt-contract.py`: closed vocabulary additions and smoke checks for `SKILL.md` plus `round-subagent-prompt.md`.
- Modify `tests/test-run-ledger.sh`: helper behavior tests for adaptive divergent assignments, target binding, outcomes, and rendered markdown.
- Modify `tests/test-release-metadata.sh`: minimal public-doc anchors for adaptive divergent analysis and cross-review gate.
- Modify `README.md`: short user-facing explanation of the two modes and the cross-review gate.
- Modify `MAINTENANCE.md`: update the existing `2026-07-03` section or add a `2026-07-04` section; do not duplicate the same date heading.

---

### Task 1: Prompt Contract For Trigger Boundaries And Protocol Terms

**Files:**
- Modify: `tests/test-prompt-contract.py`
- Modify: `test-prompts.json`

**Interfaces:**
- Consumes: current prompt contract objects with `id`, `scenario`, `prompt`, `contract`, and `expected`.
- Produces: prompt ids `1..20`, explicit generic multi-agent analysis routing, ordinary analysis non-trigger coverage, and smoke checks for the worker prompt file.

- [ ] **Step 1: Write the failing prompt-contract test changes**

In `tests/test-prompt-contract.py`, add:

```python
WORKER_PROMPT_PATH = ROOT / "round-subagent-prompt.md"
README_PATH = ROOT / "README.md"
EXPECTED_PROMPT_IDS = set(range(1, 21))
```

Add categories:

```python
    "explicit-generic-analysis-trigger",
    "ordinary-analysis-non-trigger",
    "adaptive-divergent-lenses",
    "cross-review-gate",
```

Add behaviors:

```python
    "explicit-multi-agent-precondition",
    "route-generic-analysis-to-divergent",
    "adaptive-divergent-lenses",
    "no-fixed-divergent-taxonomy",
    "target-rationale",
    "cross-review-gate",
    "cross-review-target-ids",
    "targeted-cross-examination",
    "claim-disposition",
    "worker-prompt-contract",
```

Add a new assertion function:

```python
def assert_worker_prompt_mentions_contract() -> None:
    prompt_text = WORKER_PROMPT_PATH.read_text(encoding="utf-8")
    required_terms = [
        "D1-D6",
        "C1-C6",
        "why_material",
        "expected_new_information",
        "target_id",
        "accepted",
        "modified",
        "rejected",
        "unresolved",
        "external-verification",
    ]
    for term in required_terms:
        if term not in prompt_text:
            fail(f"round-subagent-prompt.md must document {term!r}")
```

Call it from `main()` after `assert_skill_mentions_smoke_test()`.

Update `assert_skill_mentions_smoke_test()` with a small anchor set:

```python
    required_skill_terms = [
        "explicit multi-agent",
        "target-adaptive",
        "Cross-Review Gate",
        "target_id",
        "downgraded_non_decision_critical",
    ]
    for term in required_skill_terms:
        if term not in skill_text:
            fail(f"SKILL.md must document {term!r}")
```

- [ ] **Step 2: Add four prompt cases**

Append these objects to `test-prompts.json`:

```json
  {
    "id": 17,
    "scenario": "explicit Chinese generic multi-agent analysis trigger",
    "prompt": "对这个量化项目的下一步方向做多子代理分析，尽量从差异大的角度出发。",
    "contract": {
      "should_trigger": true,
      "mode": "divergent-analysis",
      "category": "explicit-generic-analysis-trigger",
      "required_behaviors": ["explicit-multi-agent-precondition", "route-generic-analysis-to-divergent", "adaptive-divergent-lenses", "dispatch-six-workers"]
    },
    "expected": "The agent treats 多子代理分析 as explicit multi-agent wording, selects divergent-analysis because the user asks for broad direction analysis rather than review, and prepares six target-adaptive lenses."
  },
  {
    "id": 18,
    "scenario": "ordinary Chinese analysis must not trigger",
    "prompt": "帮我分析一下这个量化项目的下一步方向。",
    "contract": {
      "should_trigger": false,
      "mode": null,
      "category": "ordinary-analysis-non-trigger",
      "required_behaviors": ["no-skill", "explicit-multi-agent-precondition"]
    },
    "expected": "The agent does not use orchestrating-multi-agent-analysis because the user did not ask for multi-agent, multi-subagent, or six-agent analysis."
  },
  {
    "id": 19,
    "scenario": "adaptive divergent analysis should avoid fixed taxonomy",
    "prompt": "对一个产品方向做多子代理发散分析，但不要被固定行业框架限制。",
    "contract": {
      "should_trigger": true,
      "mode": "divergent-analysis",
      "category": "adaptive-divergent-lenses",
      "required_behaviors": ["adaptive-divergent-lenses", "no-fixed-divergent-taxonomy", "target-rationale"]
    },
    "expected": "The agent chooses six materially different lenses fitted to the target instead of using a hardcoded five-category divergent taxonomy."
  },
  {
    "id": 20,
    "scenario": "review high-impact single-lens findings require target ids",
    "prompt": "对当前方案做多子代理审查。第一轮如果只有对抗式审查提出新增防护，不要直接采纳，先记录 target_id 并做交叉复审。",
    "contract": {
      "should_trigger": true,
      "mode": "review",
      "category": "cross-review-gate",
      "required_behaviors": ["cross-review-gate", "cross-review-target-ids", "targeted-cross-examination", "claim-disposition"]
    },
    "expected": "The agent keeps round one independent, records decision-critical single-lens findings as cross-review targets with target_id, and does not finalize them until they are cross-reviewed, downgraded, or externalized."
  }
```

- [ ] **Step 3: Verify RED**

Run:

```bash
python3 tests/test-prompt-contract.py
```

Expected: FAIL because `SKILL.md` and `round-subagent-prompt.md` do not yet contain the new anchors.

---

### Task 2: Adaptive Divergent Assignment Shape

**Files:**
- Modify: `tests/test-run-ledger.sh`
- Modify: `scripts/run-ledger`

**Interfaces:**
- Consumes: `prepare-round` for mode `divergent-analysis`.
- Produces: flexible round-one divergent assignments with six unique target-adaptive lenses.

- [ ] **Step 1: Add failing tests for adaptive divergent assignments**

In `tests/test-run-ledger.sh`, replace the current divergent fixed-slot test block with tests equivalent to this shell:

```bash
divergent_root="$tmpdir/.superpowers/divergent"
divergent_run="$("$LEDGER" init \
  --root "$divergent_root" \
  --mode divergent-analysis \
  --target "quant strategy next step" \
  --objective "Explore target-adaptive next directions" \
  --spawn-tool spawn \
  --wait-tool wait \
  --close-tool close \
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
```

Add the passing case:

```bash
adaptive_good="$tmpdir/adaptive-good.json"
cat >"$adaptive_good" <<'JSON'
[
  {"slot": "D1", "lens": "Regime Detection", "question": "Which market regimes matter?", "why_material": "Regime selection can change the research path.", "expected_new_information": "Regimes worth isolating before model work."},
  {"slot": "D2", "lens": "Data Leakage Risk", "question": "Where can leakage enter?", "why_material": "Leakage can invalidate apparent alpha.", "expected_new_information": "Leakage paths and controls needed before research continues."},
  {"slot": "D3", "lens": "Execution Reality", "question": "Can this trade after costs?", "why_material": "Backtests can fail after fees, slippage, latency, and capacity.", "expected_new_information": "Execution constraints that change feasibility."},
  {"slot": "D4", "lens": "Research Throughput", "question": "What speeds up iteration?", "why_material": "The next direction depends on how quickly evidence can be produced.", "expected_new_information": "Bottlenecks in data, compute, labeling, and review loops."},
  {"slot": "D5", "lens": "Overfitting Risk", "question": "Where is the strategy overfit?", "why_material": "Overfitting determines whether more search is useful.", "expected_new_information": "Falsification tests for fragile alpha."},
  {"slot": "D6", "lens": "Portfolio Fit", "question": "Does this diversify existing bets?", "why_material": "A weaker standalone strategy can still be valuable if diversifying.", "expected_new_information": "Correlation and allocation questions for the next step."}
]
JSON

"$LEDGER" prepare-round --run-dir "$divergent_run" --round 1 --assignments "$adaptive_good" >/dev/null
```

Add a duplicate-lens rejection:

```bash
duplicate_lens="$tmpdir/adaptive-duplicate-lens.json"
python3 - "$adaptive_good" "$duplicate_lens" <<'PY'
import json
import sys
src, dst = sys.argv[1], sys.argv[2]
payload = json.load(open(src, encoding="utf-8"))
payload[1]["lens"] = payload[0]["lens"]
json.dump(payload, open(dst, "w", encoding="utf-8"), indent=2)
PY

duplicate_run="$("$LEDGER" init \
  --root "$divergent_root" \
  --mode divergent-analysis \
  --target "duplicate lens check" \
  --objective "Reject duplicated lenses" \
  --spawn-tool spawn \
  --wait-tool wait \
  --close-tool close \
  --title "Duplicate lens")"

if "$LEDGER" prepare-round --run-dir "$duplicate_run" --round 1 --assignments "$duplicate_lens" >/dev/null 2>&1; then
  echo "divergent round 1 should reject duplicate lens labels" >&2
  exit 1
fi
```

- [ ] **Step 2: Verify RED**

Run:

```bash
bash tests/test-run-ledger.sh
```

Expected: FAIL because current helper requires fixed `S1-S6` divergent slots.

- [ ] **Step 3: Implement adaptive divergent assignment checks**

In `scripts/run-ledger`, remove `DIVERGENT_ROUND_ONE_LENSES` and `DIVERGENT_WILDCARD_KEYS`. Add:

```python
DIVERGENT_ROUND_ONE_REQUIRED_KEYS = ["why_material", "expected_new_information"]
```

Add:

```python
def validate_unique_lenses(assignments: list[dict[str, Any]]) -> None:
    lenses = [item["lens"] for item in assignments]
    if len(set(lenses)) != len(lenses):
        raise SystemExit("assignments must use six unique lens labels")


def validate_divergent_round_one(assignments: list[dict[str, Any]]) -> None:
    validate_unique_lenses(assignments)
    for index, item in enumerate(assignments, start=1):
        for key in DIVERGENT_ROUND_ONE_REQUIRED_KEYS:
            require_text(item.get(key), key, index)
```

Change `validate_round_one_lenses()` to:

```python
def validate_round_one_lenses(assignments: list[dict[str, Any]], mode: str) -> None:
    if mode == "divergent-analysis":
        validate_divergent_round_one(assignments)
        return

    expected = REVIEW_ROUND_ONE_LENSES
    expected_slots = list(expected)
    actual_slots = [item["slot"] for item in assignments]
    if actual_slots != expected_slots:
        raise SystemExit(
            f"{mode} round 1 slots must be exactly {', '.join(expected_slots)} in order"
        )
    for item in assignments:
        expected_lens = expected[item["slot"]]
        if item["lens"] != expected_lens:
            raise SystemExit(
                f"{item['slot']} lens must be {expected_lens!r}, got {item['lens']!r}"
            )
```

- [ ] **Step 4: Verify GREEN for adaptive divergent assignment shape**

Run:

```bash
bash tests/test-run-ledger.sh
```

Expected: PASS until later tasks add new failing cross-review assertions.

---

### Task 3: Claim-Level Cross-Review Integrity And Rendering

**Files:**
- Modify: `tests/test-run-ledger.sh`
- Modify: `scripts/run-ledger`

**Interfaces:**
- Consumes: `record-synthesis`, `prepare-round`, and `finalize-round`.
- Produces: declared cross-review targets that can be traced by `target_id` from synthesis to round-two assignments, outcomes, finalization status, and rendered markdown.

- [ ] **Step 1: Add test fixtures for a completed review round**

In `tests/test-run-ledger.sh`, add a helper block that creates a completed review round using the existing six-review assignment fixture:

```bash
cross_root="$tmpdir/.superpowers/cross-review"
cross_run="$("$LEDGER" init \
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
```

- [ ] **Step 2: Add failing test for declared target blocking stop**

Add:

```bash
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

"$LEDGER" record-synthesis --run-dir "$cross_run" --round 1 --synthesis "$needs_cross_review" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision stop --summary "Stop with pending target" >/dev/null 2>&1; then
  echo "finalize-round should reject stop while cross_review_gate_status needs_cross_review" >&2
  exit 1
fi

"$LEDGER" finalize-round --run-dir "$cross_run" --round 1 --decision continue_round_2 --summary "Cross-review cr-guardrail." >/dev/null
```

- [ ] **Step 3: Add failing tests for round-two target binding**

Add:

```bash
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
```

Add the passing round-two assignment:

```bash
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
```

- [ ] **Step 4: Add failing tests for outcome status and markdown rendering**

Complete round two:

```bash
for slot in C1 C2 C3 C4 C5 C6; do
  "$LEDGER" record-spawn --run-dir "$cross_run" --round 2 --slot "$slot" --agent-id "agent-$slot" --status spawned >/dev/null
  "$LEDGER" record-result --run-dir "$cross_run" --round 2 --slot "$slot" --status completed --summary "$slot result" >/dev/null
  "$LEDGER" record-close --run-dir "$cross_run" --round 2 --slot "$slot" --status closed >/dev/null
done
```

Add an unresolved outcome that must block stop:

```bash
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

"$LEDGER" record-synthesis --run-dir "$cross_run" --round 2 --synthesis "$unresolved_outcome" >/dev/null

if "$LEDGER" finalize-round --run-dir "$cross_run" --round 2 --decision stop --summary "Stop unresolved" >/dev/null 2>&1; then
  echo "finalize-round should reject stop with unresolved cross-review outcome" >&2
  exit 1
fi
```

Create a separate successful run or mutate a fresh round-two test run with:

```json
{
  "cross_review_gate_status": "clear",
  "cross_review_outcomes": [
    {"target_id": "cr-guardrail", "status": "modified", "rationale": "Use a lightweight checklist instead of a mandatory guardrail."}
  ]
}
```

Then assert `round-02.md` includes:

```bash
if ! grep -q "Cross Review Gate Status" "$cross_run/round-02.md"; then
  echo "round markdown should render cross review gate status" >&2
  exit 1
fi
if ! grep -q "cr-guardrail" "$cross_run/round-02.md"; then
  echo "round markdown should render cross review target ids or outcomes" >&2
  exit 1
fi
```

- [ ] **Step 5: Verify RED**

Run:

```bash
bash tests/test-run-ledger.sh
```

Expected: FAIL because current helper rejects the new fields and has no target binding or markdown rendering.

- [ ] **Step 6: Implement synthesis constants**

In `scripts/run-ledger`, add:

```python
CROSS_REVIEW_GATE_STATUSES = {"", "clear", "needs_cross_review", "external_verification"}
CROSS_REVIEW_TARGET_DISPOSITIONS = {
    "pending",
    "downgraded_non_decision_critical",
    "external_verification",
}
CROSS_REVIEW_OUTCOME_STATUSES = {
    "accepted",
    "modified",
    "rejected",
    "unresolved",
    "external-verification",
}
CROSS_REVIEW_TARGET_FIELDS = [
    "target_id",
    "source_slot",
    "claim",
    "why_decision_critical",
    "disposition",
]
CROSS_REVIEW_OUTCOME_FIELDS = ["target_id", "status", "rationale"]
```

Add `cross_review_gate_status` to `SYNTHESIS_TEXT_FIELDS`. Add `cross_review_targets` and `cross_review_outcomes` as structured synthesis fields accepted by `validate_synthesis_payload()`.

- [ ] **Step 7: Implement target/outcome validation helpers**

Add:

```python
def validate_object_list(value: Any, key: str, fields: list[str]) -> list[dict[str, str]]:
    if not isinstance(value, list):
        raise SystemExit(f"synthesis field {key!r} must be an array")
    output: list[dict[str, str]] = []
    for index, item in enumerate(value, start=1):
        if not isinstance(item, dict):
            raise SystemExit(f"synthesis field {key!r} item {index} must be an object")
        row: dict[str, str] = {}
        for field in fields:
            row[field] = require_text(item.get(field), f"{key}.{field}", index)
        output.append(row)
    return output


def target_ids_from_targets(targets: Any) -> set[str]:
    if not isinstance(targets, list):
        return set()
    return {str(item.get("target_id")) for item in targets if isinstance(item, dict) and item.get("target_id")}


def pending_target_ids(targets: Any) -> set[str]:
    if not isinstance(targets, list):
        return set()
    ids: set[str] = set()
    for item in targets:
        if not isinstance(item, dict):
            continue
        if item.get("disposition") == "pending":
            ids.add(str(item.get("target_id")))
    return ids
```

During synthesis validation:

```python
if key == "cross_review_targets":
    targets = validate_object_list(value, key, CROSS_REVIEW_TARGET_FIELDS)
    for item in targets:
        if item["disposition"] not in CROSS_REVIEW_TARGET_DISPOSITIONS:
            raise SystemExit("cross_review_targets disposition is invalid")
    validated[key] = targets
elif key == "cross_review_outcomes":
    outcomes = validate_object_list(value, key, CROSS_REVIEW_OUTCOME_FIELDS)
    for item in outcomes:
        if item["status"] not in CROSS_REVIEW_OUTCOME_STATUSES:
            raise SystemExit("cross_review_outcomes status is invalid")
    validated[key] = outcomes
```

- [ ] **Step 8: Implement finalization gate checks**

Add:

```python
def validate_cross_review_finalization(round_doc: dict[str, Any], decision: str) -> None:
    synthesis = round_doc.get("synthesis") or {}
    gate_status = str(synthesis.get("cross_review_gate_status") or "")
    if gate_status not in CROSS_REVIEW_GATE_STATUSES:
        raise SystemExit("cross_review_gate_status is invalid")
    if decision != "stop":
        return
    if gate_status == "needs_cross_review":
        raise SystemExit("cannot stop while cross_review_gate_status needs_cross_review")

    outcomes = synthesis.get("cross_review_outcomes") or []
    if isinstance(outcomes, list):
        unresolved = [
            str(item.get("target_id"))
            for item in outcomes
            if isinstance(item, dict) and item.get("status") == "unresolved"
        ]
        if unresolved:
            raise SystemExit("cannot stop with unresolved cross-review outcomes: " + ", ".join(unresolved))
        external = [
            str(item.get("target_id"))
            for item in outcomes
            if isinstance(item, dict) and item.get("status") == "external-verification"
        ]
        if external and gate_status != "external_verification":
            raise SystemExit("external-verification outcomes require cross_review_gate_status external_verification")
```

Call it in `command_finalize_round()` for non-blocked rounds before writing final state.

- [ ] **Step 9: Implement round-two target coverage**

Add:

```python
def previous_round_pending_targets(run_dir: Path, round_number: int) -> set[str]:
    if round_number != 2:
        return set()
    previous = load_round(run_dir, 1)
    synthesis = previous.get("synthesis") or {}
    if synthesis.get("cross_review_gate_status") != "needs_cross_review":
        return set()
    return pending_target_ids(synthesis.get("cross_review_targets"))


def validate_cross_review_round_assignments(assignments: list[dict[str, Any]], required_target_ids: set[str]) -> None:
    if not required_target_ids:
        return
    assigned: set[str] = set()
    for index, item in enumerate(assignments, start=1):
        target_id = require_text(item.get("target_id"), "target_id", index)
        if target_id not in required_target_ids:
            raise SystemExit(f"assignment {index} references unknown cross-review target_id {target_id!r}")
        assigned.add(target_id)
    missing = required_target_ids - assigned
    if missing:
        raise SystemExit("round 2 assignments do not cover cross-review target ids: " + ", ".join(sorted(missing)))
```

In `command_prepare_round()`, after base assignment validation:

```python
    required_target_ids = previous_round_pending_targets(run_dir, round_number)
    validate_cross_review_round_assignments(assignments, required_target_ids)
```

- [ ] **Step 10: Render cross-review fields**

Update the default synthesis scaffold in `command_prepare_round()`:

```python
            "cross_review_gate_status": "",
            "cross_review_targets": [],
            "cross_review_outcomes": [],
```

Add markdown sections in `render_round_markdown()`:

```python
### Cross Review Gate Status

{markdown_field(synthesis.get("cross_review_gate_status"))}

### Cross Review Targets

{markdown_object_list(synthesis.get("cross_review_targets"))}

### Cross Review Outcomes

{markdown_object_list(synthesis.get("cross_review_outcomes"))}
```

Add helper:

```python
def markdown_object_list(value: Any) -> str:
    if not isinstance(value, list):
        return "- None recorded"
    lines: list[str] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        parts = [f"{key}={item[key]}" for key in sorted(item) if non_empty_text(item.get(key))]
        if parts:
            lines.append("- " + "; ".join(parts))
    return "\n".join(lines) if lines else "- None recorded"
```

- [ ] **Step 11: Verify GREEN**

Run:

```bash
bash tests/test-run-ledger.sh
```

Expected: PASS.

---

### Task 4: Runtime Skill And Worker Prompt Protocol

**Files:**
- Modify: `SKILL.md`
- Modify: `round-subagent-prompt.md`

**Interfaces:**
- Consumes: behavior enforced by Tasks 1-3.
- Produces: the runtime protocol future agents must follow.

- [ ] **Step 1: Update trigger boundary in `SKILL.md`**

Use this wording:

```markdown
Use this skill only when the user explicitly asks for multi-agent, multi-subagent, or six-agent analysis of the same target. The word `analysis` or `分析` alone is not enough.

Mode selection:

- Use `review` when explicit multi-agent wording is paired with `审查`, `评审`, `review`, or a request to stress-test an existing plan, implementation proposal, spec, skill, artifact, or decision.
- Use `divergent-analysis` when explicit multi-agent wording is paired with `分析`, `发散分析`, `analysis`, `divergent analysis`, or a request for materially different angles on a target direction, project, product, strategy, research plan, or next-step question.
- If the user says generic `多子代理分析`, `多代理分析`, `六代理分析`, or `multi-agent analysis` without review wording, default to `divergent-analysis`.
- If wording and target conflict, ask one concise clarification question before creating a run record.
```

- [ ] **Step 2: Replace divergent-analysis fixed taxonomy**

Use:

```markdown
Round 1 must use exactly six target-adaptive subagents. The main agent chooses the lenses after reading the target and objective. Do not use a fixed product-centric taxonomy.

Each assignment must include:

- `slot`: unique slot label, normally `D1` through `D6`
- `lens`: concise target-specific angle name
- `question`: the exact question this worker must answer
- `why_material`: why this angle can change understanding, priority, or decision
- `expected_new_information`: what new information this worker should add

The main agent should also check distinctness before dispatch: each lens should examine a different mechanism, stakeholder, evidence source, time horizon, failure mode, or value function. This distinctness check is judgment, not string matching.
```

- [ ] **Step 3: Add Cross-Review Gate protocol**

Add:

```markdown
## Cross-Review Gate

Round 1 workers stay independent. Independence surfaces raw signals; it does not make a single-lens recommendation final.

After synthesis, the main agent must identify decision-critical single-lens claims and decision-critical lens conflicts. Each unresolved item that needs reciprocal review becomes a `cross_review_target` with:

- `target_id`
- `source_slot`
- `claim`
- `why_decision_critical`
- `disposition`: `pending`, `downgraded_non_decision_critical`, or `external_verification`

Use `downgraded_non_decision_critical` when the claim is worth recording but does not change the current decision. Use `external_verification` when more analysis cannot resolve the claim and real tests, data, environment access, or user confirmation are required.

If any target has `disposition: pending`, set `cross_review_gate_status` to `needs_cross_review` and continue to Round 2. Round 2 is targeted cross-examination. Use `C1` through `C6` slots, and every assignment must reference a pending `target_id` from Round 1. Multiple workers may examine the same target through different lenses, but every pending target must receive at least one worker.

Round 2 synthesis records `cross_review_outcomes` with:

- `target_id`
- `status`: `accepted`, `modified`, `rejected`, `unresolved`, or `external-verification`
- `rationale`

Do not stop while `cross_review_gate_status` is `needs_cross_review` or while any outcome is `unresolved`. Stop is allowed when pending claims have been accepted, modified, rejected, downgraded, or externalized.
```

- [ ] **Step 4: Update continuation and stop rules**

Add:

```markdown
Round 2 runs automatically when `cross_review_gate_status` is `needs_cross_review`.

Stop only when:

- no pending cross-review target remains, and
- no cross-review outcome is `unresolved`, and
- remaining work is implementation, user choice, or external verification rather than more analysis.
```

- [ ] **Step 5: Update `round-subagent-prompt.md`**

Change the slot hint to include:

```markdown
Slot: [A1-A6, D1-D6, or C1-C6]
```

Add:

```markdown
For divergent-analysis mode:

- Treat the assigned `lens` as the full scope of your work.
- Use `why_material` and `expected_new_information` to stay focused.
- Do not switch to a generic taxonomy unless it is explicitly assigned.

For targeted cross-review assignments:

- Start from the provided `target_id` and source claim.
- Apply only the assigned lens to that target.
- Return one recommended status: `accepted`, `modified`, `rejected`, `unresolved`, or `external-verification`.
- Explain the minimum reasoning needed for that status.
- Do not introduce unrelated analysis unless it changes the status of the target.
```

- [ ] **Step 6: Verify prompt contract GREEN**

Run:

```bash
python3 tests/test-prompt-contract.py
```

Expected: PASS.

---

### Task 5: Public Documentation And Release Metadata

**Files:**
- Modify: `README.md`
- Modify: `MAINTENANCE.md`
- Modify: `tests/test-release-metadata.sh`

**Interfaces:**
- Consumes: protocol text from Task 4.
- Produces: public-facing docs and simple release metadata checks.

- [ ] **Step 1: Add release metadata assertions**

In `tests/test-release-metadata.sh`, add:

```bash
if ! grep -q "target-adaptive" README.md; then
  echo "README must describe target-adaptive divergent analysis" >&2
  exit 1
fi

if ! grep -q "Cross-Review Gate" README.md; then
  echo "README must describe Cross-Review Gate" >&2
  exit 1
fi

if ! grep -q "target_id" MAINTENANCE.md; then
  echo "MAINTENANCE must mention claim-level target_id tracking" >&2
  exit 1
fi
```

- [ ] **Step 2: Update README**

Replace the divergent section with:

```markdown
`divergent-analysis` explores materially different angles for a target direction, project, product, strategy, research plan, or next-step question.

Round 1 uses six target-adaptive lenses chosen by the main agent. Each lens records why it matters and what new information it should add. This keeps the mode useful for product work, quantitative research, architecture decisions, and other domains without locking it to a fixed taxonomy.
```

Add:

```markdown
## Cross-Review Gate

First-round workers stay independent. If a high-impact claim appears from one lens or if lenses conflict on a decision-critical action, the claim is recorded with a `target_id`. Pending targets are cross-reviewed in a targeted second round, downgraded as non-decision-critical, or moved to external verification.

Cross-reviewed claims are classified as `accepted`, `modified`, `rejected`, `unresolved`, or `external-verification`.
```

- [ ] **Step 3: Update MAINTENANCE**

Add a `2026-07-04` entry, or extend the existing latest dated section if it already covers this work:

```markdown
### 2026-07-04

- Changed divergent-analysis round-one lenses from fixed categories to target-adaptive lenses.
- Preserved explicit multi-agent wording as the trigger precondition; ordinary analysis requests remain non-triggers.
- Added claim-level `target_id` tracking for Cross-Review Gate targets and outcomes.
- Added markdown rendering expectations for cross-review gate state, targets, and outcomes.
```

- [ ] **Step 4: Verify release metadata**

Run:

```bash
bash tests/test-release-metadata.sh
```

Expected: PASS.

---

### Task 6: Full Verification

**Files:**
- Verify all modified files.

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: a working tree ready for review, commit, or push when requested.

- [ ] **Step 1: Run full verification**

Run:

```bash
python3 tests/test-prompt-contract.py
bash tests/test-run-ledger.sh
bash tests/test-release-metadata.sh
python3 -m py_compile scripts/run-ledger tests/test-prompt-contract.py
bash -n tests/test-run-ledger.sh
bash -n tests/test-release-metadata.sh
git diff --check
```

Expected output includes:

```text
prompt contract smoke suite looks good (20 cases)
orchestrating-multi-agent-analysis ledger helper looks good
release metadata looks good
```

- [ ] **Step 2: Inspect intended diff**

Run:

```bash
git diff --stat
git diff -- SKILL.md round-subagent-prompt.md scripts/run-ledger test-prompts.json tests/test-prompt-contract.py tests/test-run-ledger.sh tests/test-release-metadata.sh README.md MAINTENANCE.md
```

Expected: diff only covers adaptive divergent assignment shape, cross-review target integrity, rendered markdown, prompt/docs updates, and matching tests.

- [ ] **Step 3: Leave commit/push to the user request**

Run:

```bash
git status --short
```

Expected: only intentional modified files and this plan file. Do not commit or push unless the user explicitly asks.

---

## Self-Review

**Spec coverage:** This plan covers target-adaptive divergent analysis, explicit multi-agent trigger boundaries, cross-review gate handling, claim-level target binding, markdown rendering, worker prompt coverage, and public docs.

**Review coverage:** It addresses the six-agent review findings: no broad ordinary-analysis trigger, narrower helper responsibility, no exact review-lens ban, target-id binding, unresolved outcome blocking, markdown rendering, worker prompt testing, no undefined run variable, and no forced push to `main`.

**Type consistency:** The same field names are used throughout: `why_material`, `expected_new_information`, `target_id`, `cross_review_gate_status`, `cross_review_targets`, `cross_review_outcomes`, `downgraded_non_decision_critical`, and `external-verification`.
