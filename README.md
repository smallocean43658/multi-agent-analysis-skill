# Orchestrating Multi-Agent Analysis Skill

A Codex skill for running disciplined six-subagent review or divergent analysis on one target artifact, plan, decision, or question.

This skill is for situations where a normal single-agent review is not enough and the user explicitly asks for multi-agent analysis, for example:

- `对当前方案做一次多子代理审查`
- `对这个产品方向做多子代理发散分析`
- `Run a multi-agent review of docs/plan.md`
- `Use multi-agent divergent analysis to explore non-obvious angles`

## Why It Exists

Multi-agent review is useful only when it stays structured. Without a protocol, it becomes expensive brainstorming with unclear provenance.

This skill makes the process repeatable:

- Exactly six subagents per round.
- Different lenses instead of duplicate opinions.
- A local run record before dispatch.
- Explicit worker lifecycle tracking: spawn, result, close.
- Clear separation between usable results and failed or missing workers.
- A continuation gate so analysis stops when another round is unlikely to change the decision.

The goal is not to claim statistical independence. The value is controlled decomposition, traceable disagreement, and a durable record of what each worker was asked and what it returned.

## Modes

`review` stress-tests a concrete plan, implementation proposal, spec, skill, or decision.

Round 1 uses these fixed lenses:

- First Principles
- Occam's Razor
- Bounded Bayesian
- Expected Cost Optimality
- Adversarial Review
- Execution Friction

`divergent-analysis` explores materially different angles for a broad direction or decision.

Round 1 uses five fixed slots plus one constrained wildcard:

- User Behavior & Adoption
- Workflow & Operational Reality
- System Mechanics & Dependencies
- Failure, Abuse & Recovery
- Economics, Time & Opportunity Cost
- Wildcard Non-Obvious Angle

## What It Records

Every run creates a local record under:

```text
.superpowers/multi-agent-analysis/
```

Run directories use this format:

```text
YYYY-MM-DD-HHMM-<mode>-<slug>-<uuid6>/
```

Each run contains:

- `brief.md`: canonical handoff for all workers.
- `ledger.md`: chronological lifecycle log.
- `state.json`: resumable run state.
- `round-N.json`: structured round assignments, results, statuses, and synthesis.
- `round-N.md`: rendered human-readable round record.

Local run records are intentionally ignored by git.

## Install

Clone the repository and symlink it into Codex's skills directory:

```bash
git clone https://github.com/smallocean43658/multi-agent-analysis-skill.git ~/multi-agent-analysis-skill
mkdir -p ~/.codex/skills
ln -sfn ~/multi-agent-analysis-skill ~/.codex/skills/orchestrating-multi-agent-analysis
```

Restart or refresh your Codex session so the skill list is reloaded.

To update an existing install:

```bash
cd ~/multi-agent-analysis-skill
git pull --ff-only
```

## Requirements

The skill requires real worker-capable multi-agent tools in the active Codex session:

- spawn worker
- wait for worker
- close worker

The exact callable names vary by runtime. The main agent must inspect the active tool list and record those names in `state.json`. If no worker tools are available, the skill must stop instead of simulating subagents.

## Basic Use

Ask explicitly for multi-agent review or divergent analysis:

```text
对 docs/plan.md 做一次多子代理审查，重点看方案是否值得执行。
```

```text
Use multi-agent divergent analysis on this architecture decision and find non-obvious angles.
```

The main agent will:

1. Create a run record.
2. Prepare exactly six assignments.
3. Dispatch six workers through the active multi-agent tools.
4. Record spawn, result, and close lifecycle events.
5. Write structured synthesis.
6. Stop or continue only if the continuation gate is satisfied.

Round 3 and Round 4 require explicit user approval. Round 4 is the hard cap.

## Helper Commands

The bundled helper is `scripts/run-ledger`. It owns mechanical validation and record rendering.

Common commands:

```bash
scripts/run-ledger init
scripts/run-ledger prepare-round
scripts/run-ledger record-spawn
scripts/run-ledger record-result
scripts/run-ledger record-close
scripts/run-ledger record-synthesis
scripts/run-ledger finalize-round
scripts/run-ledger status
```

For the full protocol, read `SKILL.md`.

## Validate

Run the smoke tests after changing triggers, modes, lifecycle behavior, synthesis rules, or continuation rules:

```bash
python3 tests/test-prompt-contract.py
bash tests/test-run-ledger.sh
```

## Repository Layout

- `SKILL.md`: the actual Codex skill instructions.
- `round-subagent-prompt.md`: worker prompt template.
- `scripts/run-ledger`: helper for run records and lifecycle validation.
- `test-prompts.json`: prompt contract corpus.
- `tests/test-prompt-contract.py`: validates trigger and mode contracts.
- `tests/test-run-ledger.sh`: validates ledger state transitions.
- `MAINTENANCE.md`: maintainer notes, change log, verification checklist, and known limits.
