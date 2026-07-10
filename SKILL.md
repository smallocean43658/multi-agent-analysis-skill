---
name: orchestrating-multi-agent-analysis
description: Use when the user explicitly asks for multi-agent, multi-subagent, or six-agent review or divergent analysis of the same target, or explicitly asks for generic multi-agent analysis that should route to divergent-analysis instead of ordinary single-agent analysis.
---

# Orchestrating Multi-Agent Analysis

## Overview

Use this skill to run a disciplined six-worker first round followed, when needed, by fresh adaptive follow-up batches over one target artifact, decision, plan, or question. It has two modes:

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
- Canonical mutable record: ordered `events` and lifecycle/synthesis/finalization data in `round-N.json`. Treat `state.json` dynamic fields, `round-N.md`, and `ledger.md` as rebuildable projections.
- Protocol: new runs store `adaptive-backlog-v1`. A pre-existing state without `protocol_version` remains `legacy-fixed-six-v1`; never migrate it implicitly.

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

The helper owns atomic file publication, per-run locking, mechanical file creation, assignment validation, lifecycle status validation, and rendering structured round JSON into projections. It validates core shape plus narrow protocol integrity: divergent rationale fields, cross-review target references, pending target coverage, outcome target ids, and terminal gate consistency. The main agent still owns judgment: mode selection, lens choice after round one, lens quality, synthesis quality, continuation decisions, and user communication.

The `brief.md` file is the canonical handoff. Put the target, objective, known constraints, source paths, and any user-provided context there. Worker prompts should refer to this file instead of pasting long briefs into each worker prompt.

## Review Mode

Use review mode for an explicit multi-agent review of a concrete plan, design, implementation proposal, skill, spec, or decision.

Round 1 must use exactly six subagents with these fixed lenses:

| Slot | Lens | Purpose |
|---|---|---|
| A1 | First Principles | Test the original objective, requirements, constraints, and completion evidence; strip the plan to goals, causal mechanics, and irreducible requirements. |
| A2 | Occam's Razor | Detect unnecessary complexity, removable mechanisms, and overfit abstractions. |
| A3 | Bounded Bayesian | Reason under limited evidence; state priors, updates, confidence, and missing evidence. |
| A4 | Expected Cost Optimality | Compare downside, upside, reversibility, opportunity cost, and cost of being wrong. |
| A5 | Adversarial Review | Attack the plan through edge cases, incentives, brittle dependencies, and abuse paths. |
| A6 | Execution Friction | Test usability, ownership, sequencing, testability, maintenance, and handoff risk. |

Do not replace, merge, or skip these lenses in round 1.

## Engineering Overlay

Use `--target-overlay engineering` only when the target needs an engineering-specific review profile. Target overlay: `engineering` is persisted as static `target_overlay`; otherwise the target overlay is none. It never selects or changes a review portfolio at runtime.

For an engineering review Round 1, retain the classic A1-A6 lenses and use this distributed engineering overlay with exact checks across their slots:

- A1: `functional-requirements`, `non-functional-requirements`, `acceptance-criteria`, `compatibility-and-platform-constraints`.
- A2: `simplest-sufficient-mechanism`, `architecture-and-ownership-boundaries`, `interfaces-data-flow-and-state`, `dependency-necessity`.
- A3: `prototype-test-and-benchmark-evidence`, `technical-assumptions`, `missing-evidence`, `falsification-conditions`.
- A4: `build-buy-and-alternative-architecture`, `implementation-and-operating-cost`, `migration-and-switching-cost`, `reversibility-and-opportunity-cost`.
- A5: `concurrency-and-data-integrity`, `security-and-abuse`, `dependency-and-capacity-failure`, `degradation-recovery-and-rollback`.
- A6: `implementation-sequence-and-ownership`, `test-strategy-and-observability`, `deployment-and-migration`, `maintenance-and-handoff`.

For engineering divergent-analysis Round 1, choose six target-adaptive D lenses but assign exactly one slot `overlay_role: engineering-feasibility`. Its `overlay_checks` must be exactly `simplest-sufficient-mechanism`, `implementation-feasibility`, `testability-and-observability`, `failure-recovery-and-reversibility`, and `maintenance-portability-and-handoff`. Do not force engineering checks or an engineering-feasibility role onto a target with no target overlay. Targeted C follow-up assignments do not carry overlay fields.

The engineering overlay adds scoped evidence checks; it does not alter the adaptive backlog, cross-review target policy, or the required objective alignment judgment.

## Divergent-Analysis Mode

Use divergent-analysis mode only when the user explicitly asks for multi-agent, multi-subagent, or six-agent divergent analysis on one target, or uses generic explicit multi-agent analysis wording that routes here under the trigger boundary. Broad angle discovery alone is not a trigger.

Round 1 must use exactly six target-adaptive subagents. The main agent chooses the lenses after reading the target and objective. Do not use a fixed product-centric taxonomy.

Across all adaptive lenses, preserve the canonical objective and make the same synthesis judgment about whether the conclusions and action list serve it.

Each assignment must include:

- `slot`: unique slot label, normally `D1` through `D6`
- `lens`: concise target-specific angle name
- `question`: the exact question this worker must answer
- `why_material`: why this angle can change understanding, priority, or decision
- `expected_new_information`: what new information this worker should add

The main agent should also check distinctness before dispatch: each lens should examine a different mechanism, stakeholder, evidence source, time horizon, failure mode, or value function. This distinctness check is judgment, not string matching.

## Cross-Review Gate

Round 1 workers stay independent. Independence surfaces raw signals; it does not make a single-lens recommendation final.

After synthesis, the main agent must identify decision-critical single-lens claims and decision-critical lens conflicts. Each newly introduced item is stored once, in its origin round, as a canonical `cross_review_target` with:

- `target_id`
- `source_slot`
- `claim`
- `why_decision_critical`
- `review_policy`: `single` for one initial reviewer or `dual` for a complete two-reviewer initial bundle
- `conflict_ref`: `null` for `single`; `critical_disagreements[N]` for `dual`, referencing an item in the same synthesis
- `disposition`: `pending`, `downgraded_non_decision_critical`, or `external_verification`

The `source_slot` must identify a spawned assignment with a completed result in the origin round. Use `downgraded_non_decision_critical` when the claim is worth recording but does not change the current decision. Use `external_verification` when more analysis cannot resolve the claim and real tests, data, environment access, or user confirmation are required.

Pending targets form a canonical creation-order backlog. The helper prepares a fresh batch of one to six `C` assignments, selecting complete target bundles until the six-seat limit is reached. Never split an initial `dual` bundle. Later rounds reference `target_id`; they do not copy the canonical target object. A target receives exactly one later tie-break seat only when its initial quota (`single: 1`, `dual: 2`) is complete and the latest outcome is `unresolved`. A `single` target has a two-reviewer maximum and a `dual` target has a three-reviewer maximum; resolve or externalize the target at exhaustion.

Round 2 synthesis records `cross_review_outcomes` with:

- `target_id`
- `status`: `accepted`, `modified`, `rejected`, `unresolved`, or `external-verification`
- `rationale`

Every adaptive follow-up synthesis contains exactly one outcome for each `active_target_id` and no outcome for unscheduled backlog targets. Resolved active targets leave the backlog; unresolved active targets remain. A follow-up synthesis may add one fresh canonical target sourced from a completed assignment in that same round.

For adaptive runs, the helper derives `cross_review_gate_status` and `next_round_decision` from canonical backlog replay. It derives `cross_review_gate_status: external_verification` when external evidence is required and no backlog remains. Caller values, when present for replay compatibility, are assertions and must match. Stop is rejected while backlog remains. Legacy runs retain caller-owned gate validation.

## Round Preparation

Create the assignment file yourself, then validate it with the helper:

```bash
scripts/run-ledger prepare-round \
  --run-dir .superpowers/multi-agent-analysis/2026-07-03-1200-review-plan-a1b2c3 \
  --round 1 \
  --assignments /tmp/round-01-assignments.json
```

For every Round 3 or later batch, ask the user first. One explicit approval authorizes one prepared round; include `--user-approved`:

```bash
scripts/run-ledger prepare-round \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 3 \
  --assignments /tmp/round-03-assignments.json \
  --user-approved
```

Round 1 assignment files contain exactly six objects. Adaptive follow-up files contain one to six objects matching the helper's complete active bundles, with consecutive slots `C1` through `CN`. Each object includes `slot`, `lens`, `question`, and `target_id`; the helper verifies and adds canonical `source_slot`, `claim`, `review_policy`, and `conflict_ref`. Each adaptive follow-up round persists `incoming_backlog_ids`, `active_target_ids`, and its variable `expected_agents` count.

Helper enforcement stays narrow: it validates assignment shape, divergent rationale fields, canonical target provenance, complete follow-up bundles, active outcome coverage, textual review limits, and derived gate consistency. The main agent must still carry richer protocol meaning and quality judgment in its assignment source and prompts:

- divergent-analysis: `why_material`, `expected_new_information`
- targeted cross-review: `target_id`, `source_slot`, `claim`

Use `round-subagent-prompt.md` as the prompt template for each worker.

If the helper rejects the assignments, fix the assignment file before dispatch. Do not dispatch a partial target bundle.

## Dispatch Lifecycle

For each round:

1. Prepare `brief.md`.
2. Prepare and validate the round's `expected_agents`: six in Round 1, one to six in an adaptive follow-up batch.
3. For adaptive runs, before each external spawn outcome, record fresh intent with `plan-dispatch --slot SLOT`. Legacy runs may retain direct pending-to-terminal spawn records for compatibility.
4. Dispatch every worker in the prepared batch. Record the returned worker id with `record-spawn --status spawned`; if the external outcome cannot be proven after a crash, record `unknown` without an agent id.
5. Wait for every spawned worker.
6. Record each result before a normal close. `record-result --status` must be `completed` or `failed`; only `completed` counts as a usable result.
7. Close every finished worker and record the close status. `record-close --status` must be `closed`, `failed`, or `cancelled`. Use `closed` only after a result exists; use `failed` or `cancelled` when a worker terminates abnormally without a result.
8. Synthesize only after `expected_agents` usable results and normal closes exist, or stop through a documented blocked path.

Use the helper commands for live bookkeeping:

```bash
scripts/run-ledger plan-dispatch \
  --run-dir .superpowers/multi-agent-analysis/<run-id> \
  --round 1 \
  --slot A1

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

For adaptive runs, `record-spawn` resolves only planned dispatches to `spawned`, `failed`, or `unknown`; `spawned` requires an agent id, and `failed` and `unknown` reject one. Legacy runs may resolve pending or planned dispatches. A spawned agent id must be unique across the run; exact replay for its original slot remains idempotent. Never retry or replace an unknown dispatch. While any assignment remains `planned`, `status` reports `resolve_planned_dispatch` and synthesis or finalization is rejected.

If a spawn, wait, or close call fails, record the failure with the helper and decide whether the run is blocked. On partial spawn failure or unknown dispatch, drain and close every worker known to have spawned before blocked finalization. The helper rejects blocked finalization while any spawned worker is still open. Do not proceed as if a missing, unknown, or failed worker returned a usable result.

## Resume And Recovery

When resuming an interrupted run, start with:

```bash
scripts/run-ledger status \
  --run-dir .superpowers/multi-agent-analysis/<run-id>
```

`status` takes the run lock and reconciles `state.json`, every `round-N.md`, and `ledger.md` from canonical round JSON before it prints a snapshot. Trust the reconciled output and latest `round-N.json` over conversation memory. Resolve every `planned` dispatch to the known spawn result or explicitly to `unknown`, then continue only missing lifecycle actions. Never retry or replace an unknown dispatch.

Exact command replays are safe: the helper returns success without adding a duplicate canonical event. A replay that changes status, agent id, summary, assignments, synthesis payload, or finalization details is rejected as a conflict. Do not edit projection files directly; run `status` to repair them after interruption.

## Synthesis Contract

After each complete round, write a synthesis into the structured fields in `round-N.json`; the helper renders those fields into `round-N.md` whenever it writes the round. Include:

- `convergence`: issues surfaced by multiple lenses
- `disagreement`: conflicts between lenses
- `critical_disagreements`: unresolved conflicts that can change the final decision
- `cannot_verify`: important claims the current round cannot validate
- `high_impact_low_evidence`: findings that matter but need more evidence
- `action_list`: concrete changes, decisions, or next checks
- `objective_alignment`: one synthesis judgment with `status` (`aligned` or `needs_revision`), a rationale, and unmet requirements; it must not repeat or map the action list
- `expected_value_of_another_round`: why another fresh follow-up batch would or would not change the decision
- `stop_reason` or `next_round_question`

For review rounds, also record the target and outcome fields needed by the current state:

- `cross_review_targets`: only targets newly introduced by this origin round
- `cross_review_outcomes`: exactly one disposition for each active target in a follow-up round

For `adaptive-backlog-v1`, omit `cross_review_gate_status` and `next_round_decision`; the helper derives both. It writes `continue_round_2` for a pending Round 1 backlog, `ask_user` for a pending Round 2+ backlog, and `stop` when no backlog remains. With no backlog, external verification derives the external gate; otherwise the gate is clear. `finalize-round --decision` asserts the derived value. Legacy synthesis supplies both fields explicitly.

Do not average away disagreement. Preserve conflicts and name the evidence that would resolve them.

For both review and divergent-analysis rounds, the main synthesis must explicitly judge whether the conclusions and action list serve the canonical run objective. The helper validates only object shape and legal continuation; it does not certify real-world effectiveness.

The first synthesis write for a mutable round must supply `objective_alignment`. A later partial correction may omit it only when the canonical synthesis already contains a valid alignment; the helper validates the merged canonical synthesis after every new correction. In adaptive runs, a correction that supplies `cross_review_targets` must preserve every existing canonical target in order and without mutation; it may append new valid target ids. Historical finalized snapshots without this field remain readable and are never assigned an inferred alignment.

For normal finalization, the helper requires non-empty `convergence`, `action_list`, `expected_value_of_another_round`, and `objective_alignment`. A `needs_revision` alignment requires unmet requirements. It is a finding about the reviewed target, not proof that the target was repaired: an adaptive run with an empty canonical backlog derives `stop` and may finalize with that finding. Continue or ask the user only when the canonical backlog or the decision process requires more work. Populate the full synthesis before calling `finalize-round`; do not use finalization as a substitute for writing the synthesis.

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

Use `--decision continue_round_2` only for a derived pending Round 1 backlog. Use `--decision ask_user` when a Round 2+ backlog remains and user approval is required before the next dispatch.

If a worker lifecycle cannot produce its `expected_agents` completed results plus normal closes, document the blocker and finalize the incomplete round with `--blocked`. Blocked rounds must stop, every planned intent must be resolved, and all known spawned workers must already have a terminal close status (`closed`, `failed`, or `cancelled`):

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

Round 2 runs automatically when the derived Round 1 decision is `continue_round_2`.

🔴 CHECKPOINT · USER APPROVAL REQUIRED: Round 3 and every later adaptive batch require fresh user approval before dispatch. Adaptive runs have no absolute round cap.

Continue only while the canonical backlog has targets with available textual review seats and the user approves the next fresh batch. Legacy runs without `protocol_version` retain exactly six follow-up workers, Round 3/4 approval, and the Round-4 cap.

Stop only when:

- no pending or unresolved canonical backlog target remains, and
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
bash tests/test-followup-protocol.sh
bash tests/test-ledger-recovery.sh
bash tests/test-run-ledger.sh
```

## Hard Blacklist

Never do these:

- Do not trigger this skill for ordinary review, planning, debugging, brainstorming, or PR review without explicit multi-agent wording.
- Do not trigger this skill for ordinary `analysis` or `分析` wording without explicit multi-agent wording.
- Do not run fewer than six workers in Round 1; adaptive follow-up batches intentionally use one to six fresh workers.
- Do not synthesize or normally finalize a round before all spawned workers have completed result records and normal close records.
- Do not finalize a blocked round while any spawned worker is still open.
- Do not record a worker result or successful close status before its spawn is recorded in `round-N.json`.
- Do not continue to Round 3 or later without fresh per-round user approval.
- Do not stop while `cross_review_gate_status` is `needs_cross_review` or while any cross-review outcome is `unresolved`.
- Do not retry or replace a failed or unknown dispatch; drain known workers and finalize the round as blocked.

## Common Mistakes

- Triggering on ordinary review language without explicit multi-agent wording.
- Triggering on ordinary `analysis` or `分析` language without explicit multi-agent wording.
- Running fewer than six workers in Round 1, or padding an adaptive follow-up batch beyond its complete target bundles.
- Pasting large briefs into every worker prompt instead of using `brief.md`.
- Reusing a fixed divergent taxonomy instead of choosing target-adaptive lenses.
- Skipping the Cross-Review Gate when a single lens makes a decision-critical claim.
- Starting Round 3 without user approval.
- Copying canonical target objects into later rounds instead of referencing their `target_id`.
- Splitting an initial `dual` review bundle or assigning a fourth textual reviewer.
- Failing to close workers after collecting results.
- Hiding worker failures in the synthesis.
