---
name: orchestrating-multi-agent-analysis
description: Use when the user explicitly asks for multi-agent, multi-subagent, or six-agent review or divergent analysis of the same target, or explicitly asks for generic multi-agent analysis that should route to divergent-analysis instead of ordinary single-agent analysis.
---

# Orchestrating Multi-Agent Analysis

## Overview

Use this skill to run a disciplined six-subagent analysis loop over one target artifact, decision, plan, or question. It has two modes:

- `review`: stress-test a concrete plan or artifact.
- `divergent-analysis`: expand the option space through target-adaptive, materially different angles.

The value is not statistical independence. The value is controlled decomposition, explicit disagreement, and durable evidence for what each worker was asked, what it returned, and why the main agent stopped or continued.

## Trigger Boundary

Use this skill only when the user explicitly asks for multi-agent, multi-subagent, or six-agent analysis of the same target. The word `analysis` or `分析` alone is not enough.

Mode selection:

- Use `review` when explicit multi-agent wording is paired with `审查`, `评审`, `review`, or a request to stress-test an existing plan, implementation proposal, spec, skill, artifact, or decision.
- Use `divergent-analysis` when explicit multi-agent wording is paired with `分析`, `发散分析`, `analysis`, `divergent analysis`, or a request for materially different angles on a target direction, project, product, strategy, research plan, or next-step question.
- If the user says generic `多子代理分析`, `多代理分析`, `六代理分析`, or `multi-agent analysis` without review wording, default to `divergent-analysis`.
- If wording and target conflict, ask one concise clarification question before creating a run record.

Do not use for ordinary single-agent review, ordinary analysis, generic planning help, brainstorming, debugging, implementation work, pull request review, or several separate tasks in parallel unless the user explicitly requests multi-agent analysis of one target.

## Required Tooling

Before dispatching workers, inspect the active tools list and identify the callable names for spawn, wait, and close. Use those exact callable names and record them in `state.json`.

Do not hardcode one namespace. In some sessions the callable names may be bare; in others they may be namespaced. The runtime tools list is the authority.

🔴 CHECKPOINT · STOP: If no worker-capable multi-agent tools are available, stop and report the blocker. Do not simulate six subagents, do not invent worker results, and do not silently downgrade this skill to single-agent analysis.

Required `state.json.tooling` shape:

```json
{
  "tooling": {
    "spawn": "<callable spawn tool from active tools list>",
    "wait": "<callable wait tool from active tools list>",
    "close": "<callable close tool from active tools list>"
  }
}
```

## Run Record

Every run must create a local record before the first dispatch:

- Root: `.superpowers/multi-agent-analysis/`
- Run directory format: `YYYY-MM-DD-HHMM-<mode>-<slug>-<uuid6>/`
- Required files at initialization: `brief.md`, `ledger.md`, `state.json`
- Required round files: `round-N.json` and `round-N.md` where `N` is the round number rendered by the helper as `round-01.json`, `round-01.md`, and so on.

Resolve helper paths relative to this `SKILL.md` file. Use the bundled helper when available:

```bash
scripts/run-ledger init \
  --root .superpowers/multi-agent-analysis \
  --mode review \
  --target docs/plan.md \
  --objective "Decide whether the plan is ready" \
  --spawn-tool "$SPAWN_TOOL" \
  --wait-tool "$WAIT_TOOL" \
  --close-tool "$CLOSE_TOOL"
```

The helper owns only mechanical file creation, assignment validation, lifecycle status validation, and rendering structured round JSON into markdown. It validates core shape plus narrow protocol integrity: divergent rationale fields, cross-review target references, pending target coverage, outcome target ids, and terminal gate consistency. The main agent still owns judgment: mode selection, lens choice after round one, lens quality, synthesis quality, continuation decisions, and user communication.

The `brief.md` file is the canonical handoff. Put the target, objective, known constraints, source paths, and any user-provided context there. Worker prompts should refer to this file instead of pasting long briefs into each worker prompt.

## Review Mode

Use review mode for an explicit multi-agent review of a concrete plan, design, implementation proposal, skill, spec, or decision.

Round 1 must use exactly six subagents with these fixed lenses:

| Slot | Lens | Purpose |
|---|---|---|
| A1 | First Principles | Strip the plan to goals, constraints, causal mechanics, and irreducible requirements. |
| A2 | Occam's Razor | Detect unnecessary complexity, removable mechanisms, and overfit abstractions. |
| A3 | Bounded Bayesian | Reason under limited evidence; state priors, updates, confidence, and missing evidence. |
| A4 | Expected Cost Optimality | Compare downside, upside, reversibility, opportunity cost, and cost of being wrong. |
| A5 | Adversarial Review | Attack the plan through edge cases, incentives, brittle dependencies, and abuse paths. |
| A6 | Execution Friction | Test usability, ownership, sequencing, testability, maintenance, and handoff risk. |

Do not replace, merge, or skip these lenses in round 1.

## Divergent-Analysis Mode

Use divergent-analysis mode only when the user explicitly asks for multi-agent, multi-subagent, or six-agent divergent analysis on one target, or uses generic explicit multi-agent analysis wording that routes here under the trigger boundary. Broad angle discovery alone is not a trigger.

Round 1 must use exactly six target-adaptive subagents. The main agent chooses the lenses after reading the target and objective. Do not use a fixed product-centric taxonomy.

Each assignment must include:

- `slot`: unique slot label, normally `D1` through `D6`
- `lens`: concise target-specific angle name
- `question`: the exact question this worker must answer
- `why_material`: why this angle can change understanding, priority, or decision
- `expected_new_information`: what new information this worker should add

The main agent should also check distinctness before dispatch: each lens should examine a different mechanism, stakeholder, evidence source, time horizon, failure mode, or value function. This distinctness check is judgment, not string matching.

## Cross-Review Gate

Round 1 workers stay independent. Independence surfaces raw signals; it does not make a single-lens recommendation final.

After synthesis, the main agent must identify decision-critical single-lens claims and decision-critical lens conflicts. Each unresolved item that needs reciprocal review becomes a `cross_review_target` with:

- `target_id`
- `source_slot`
- `claim`
- `why_decision_critical`
- `disposition`: `pending`, `downgraded_non_decision_critical`, or `external_verification`

Use `downgraded_non_decision_critical` when the claim is worth recording but does not change the current decision. Use `external_verification` when more analysis cannot resolve the claim and real tests, data, environment access, or user confirmation are required.

If any target has `disposition: pending`, set `cross_review_gate_status` to `needs_cross_review` and continue to Round 2. Round 2 is targeted cross-examination. Use `C1` through `C6` slots exactly, and every assignment must reference a pending `target_id` from Round 1. Multiple workers may examine the same target through different lenses, but every pending target must receive at least one worker.

Round 2 synthesis records `cross_review_outcomes` with:

- `target_id`
- `status`: `accepted`, `modified`, `rejected`, `unresolved`, or `external-verification`
- `rationale`

Do not finalize while the current synthesis still contains any `cross_review_targets` with `disposition: pending` unless `cross_review_gate_status` is `needs_cross_review` and the decision is `continue_round_2`; and `cross_review_gate_status` cannot be `needs_cross_review` without at least one pending target. Stop is allowed only when pending claims have been accepted, modified, rejected, downgraded, or externalized.

If one or more cross-review outcomes are `external-verification` and no targets remain `pending` or `unresolved`, set `cross_review_gate_status` to `external_verification`. Likewise, if the current synthesis stops with one or more `cross_review_targets` marked `external_verification`, `cross_review_gate_status` must be `external_verification`.

## Round Preparation

Create the assignment file yourself, then validate it with the helper:

```bash
scripts/run-ledger prepare-round \
  --run-dir .superpowers/multi-agent-analysis/2026-07-03-1200-review-plan-a1b2c3 \
  --round 1 \
  --assignments /tmp/round-01-assignments.json
```

For Round 3 or Round 4, ask the user first. After explicit approval, include `--user-approved`:

```bash
scripts/run-ledger prepare-round \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 3 \
  --assignments /tmp/round-03-assignments.json \
  --user-approved
```

The assignment file must be a JSON array with exactly six objects. Each object must include `slot`, `lens`, and `question`. Use `A1` through `A6` for review round 1, `D1` through `D6` for divergent-analysis round 1, and `C1` through `C6` for targeted cross-review rounds.

Helper enforcement stays narrow: the helper validates exactly six assignments plus the core `slot` / `lens` / `question` shape, divergent rationale fields, targeted cross-review `target_id` references, pending target coverage, outcome target ids, and terminal gate consistency. The main agent must still carry richer protocol meaning and quality judgment in its assignment source and prompts:

- divergent-analysis: `why_material`, `expected_new_information`
- targeted cross-review: `target_id`, `source_slot`, `claim`

Use `round-subagent-prompt.md` as the prompt template for each worker.

If the helper rejects the assignments, fix the assignment file before dispatch. Do not dispatch a partial round.

## Dispatch Lifecycle

For each round:

1. Prepare `brief.md`.
2. Prepare and validate exactly six assignments.
3. Dispatch all six workers. If the API allows batch calls, dispatch them in one batch. Otherwise spawn them one after another without waiting between successful spawns.
4. Record every spawned agent id and its callable tool name in `round-N.json` and `ledger.md` before waiting.
5. Wait for every spawned worker.
6. Record each result before a normal close. `record-result --status` must be `completed` or `failed`; only `completed` counts as a usable result.
7. Close every finished worker and record the close status. `record-close --status` must be `closed`, `failed`, or `cancelled`. Use `closed` only after a result exists; use `failed` or `cancelled` when a worker terminates abnormally without a result.
8. Synthesize only after six usable results exist or after a documented blocked path stops the run.

Use the helper commands for live bookkeeping:

```bash
scripts/run-ledger record-spawn \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --slot A1 \
  --agent-id <agent-id> \
  --status spawned

scripts/run-ledger record-result \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --slot A1 \
  --status completed \
  --summary "Short factual result summary"

scripts/run-ledger record-close \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --slot A1 \
  --status closed
```

If a spawn, wait, or close call fails, record the failure with the helper and decide whether the run is blocked. On partial spawn failure, drain and close every worker that already spawned before reporting the run as blocked. The helper rejects blocked finalization while any spawned worker is still open. Do not proceed as if a missing or failed worker returned a usable result.

## Resume And Recovery

When resuming an interrupted run, start with:

```bash
scripts/run-ledger status \
  --run-dir .superpowers/multi-agent-analysis/<run-id>
```

Trust `state.json` and the latest `round-N.json` over conversation memory. Continue only the missing lifecycle actions: wait for spawned-but-unrecorded workers, record returned results, close finished workers, and then synthesize. Do not dispatch replacement workers unless the prior round is explicitly marked blocked and the user agrees to restart the round.

## Synthesis Contract

After each complete round, write a synthesis into the structured fields in `round-N.json`; the helper renders those fields into `round-N.md` whenever it writes the round. Include:

- `convergence`: issues surfaced by multiple lenses
- `disagreement`: conflicts between lenses
- `critical_disagreements`: unresolved conflicts that can change the final decision
- `cannot_verify`: important claims the current round cannot validate
- `high_impact_low_evidence`: findings that matter but need more evidence
- `action_list`: concrete changes, decisions, or next checks
- `expected_value_of_another_round`: why another six-agent round would or would not change the decision
- `next_round_decision`: `stop`, `continue_round_2`, or `ask_user`
- `stop_reason` or `next_round_question`

For review rounds, also record any cross-review gating fields needed by the current state:

- `cross_review_gate_status`: `clear`, `needs_cross_review`, or `external_verification`
- `cross_review_targets`: round-1 items promoted for reciprocal review
- `cross_review_outcomes`: round-2 dispositions for each `target_id`

If the round stops because evidence needs to be gathered externally, set `cross_review_gate_status` to `external_verification`.

Do not average away disagreement. Preserve conflicts and name the evidence that would resolve them.

For normal finalization, the helper requires non-empty `convergence`, `action_list`, and `expected_value_of_another_round`. Populate the full synthesis before calling `finalize-round`; do not use finalization as a substitute for writing the synthesis.

Record the synthesis with a JSON object, then let the helper render `round-N.md`:

```bash
scripts/run-ledger record-synthesis \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --synthesis /tmp/round-01-synthesis.json
```

After the synthesis is written, mark the round decision:

```bash
scripts/run-ledger finalize-round \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --decision stop \
  --summary "Actionable recommendation exists; no decision-critical disagreement remains."
```

Use `--decision continue_round_2` only when the continuation gate is satisfied. Use `--decision ask_user` when user approval is required before the next dispatch.

If a worker lifecycle is blocked and cannot produce six completed result records plus six normal close records, document the blocker and finalize the incomplete round with `--blocked`. Blocked rounds must stop, and all successfully spawned workers must already have a terminal close status (`closed`, `failed`, or `cancelled`):

```bash
scripts/run-ledger finalize-round \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --decision stop \
  --summary "Worker dispatch failed; user input is required before restarting analysis." \
  --blocked
```

## Continuation Gate

Round 1 runs when the skill is triggered and prerequisites are satisfied.

Round 2 runs automatically when `cross_review_gate_status` is `needs_cross_review`.

🔴 CHECKPOINT · USER APPROVAL REQUIRED: Round 3 and later require user approval before dispatch. Round 4 is the absolute cap and also requires user approval.

After targeted cross-review, continue to Round 3 or Round 4 only when a narrower unresolved analysis question is still decision-critical, six fresh assignments are still materially non-duplicative, and the user explicitly approves the next round.

Stop only when:

- no pending cross-review target remains, and
- no cross-review outcome is `unresolved`, and
- remaining work is implementation, user choice, or external verification rather than more analysis.

If the tool lifecycle is incomplete and the missing result would affect synthesis integrity, do not continue analysis. Record the blocker and stop through the blocked-round path instead of pretending the gate is satisfied.

## User-Facing Reporting

After a round, report:

- Run record path.
- Short synthesis of convergence and major disagreement.
- Concrete action list.
- Whether the run stopped or why another round is justified.

For Chinese user requests, answer in Chinese unless the user asks otherwise.

## Validation

`test-prompts.json` is the maintained prompt-corpus contract for trigger, non-trigger, mode, blocked, and continuation-gate expectations. It protects the example suite from drifting, but it does not replace live dispatch testing. After changing trigger boundaries, modes, recovery behavior, or round continuation rules, run:

```bash
python3 tests/test-prompt-contract.py
bash tests/test-run-ledger.sh
```

## Hard Blacklist

Never do these:

- Do not trigger this skill for ordinary review, planning, debugging, brainstorming, or PR review without explicit multi-agent wording.
- Do not trigger this skill for ordinary `analysis` or `分析` wording without explicit multi-agent wording.
- Do not run fewer than six workers while claiming this skill was used.
- Do not synthesize or normally finalize a round before all spawned workers have completed result records and normal close records.
- Do not finalize a blocked round while any spawned worker is still open.
- Do not record a worker result or successful close status before its spawn is recorded in `round-N.json`.
- Do not continue to Round 3 or Round 4 without user approval.
- Do not stop while `cross_review_gate_status` is `needs_cross_review` or while any cross-review outcome is `unresolved`.
- Do not replace a failed worker silently; report the blocked lifecycle and ask before restarting the round.

## Common Mistakes

- Triggering on ordinary review language without explicit multi-agent wording.
- Triggering on ordinary `analysis` or `分析` language without explicit multi-agent wording.
- Running fewer than six workers while still claiming this skill was used.
- Pasting large briefs into every worker prompt instead of using `brief.md`.
- Reusing a fixed divergent taxonomy instead of choosing target-adaptive lenses.
- Skipping the Cross-Review Gate when a single lens makes a decision-critical claim.
- Starting Round 3 without user approval.
- Failing to close workers after collecting results.
- Hiding worker failures in the synthesis.
