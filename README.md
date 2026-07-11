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

- Round 1 uses exactly six workers.
- Review mode uses one fixed B1-B6 decision chain.
- Different dimensions instead of duplicate opinions; engineering review distributes one engineering overlay across B1-B6.
- Divergent engineering analysis assigns exactly one engineering-feasibility role.
- A local run record before dispatch.
- Explicit fresh-worker lifecycle tracking: spawn, result, close.
- Clear separation between usable results and failed or missing workers.
- A continuation gate and pending backlog so analysis stops when another round is unlikely to change the decision.

The goal is not to claim statistical independence. The value is controlled decomposition, traceable disagreement, and a durable record of what each worker was asked and what it returned.

## Modes

`review` stress-tests a concrete plan, implementation proposal, spec, skill, or decision.

Round 1 uses this fixed decision chain:

- B1: Goal And Requirement Alignment
- B2: Mechanism And Structural Validity
- B3: Evidence And Uncertainty Audit
- B4: Alternatives And Decision Value
- B5: Risk And Robustness
- B6: Execution And Lifecycle

`divergent-analysis` explores materially different angles for a target direction, project, product, strategy, research plan, or next-step question.

Round 1 uses six target-adaptive lenses chosen by the main agent. Each lens records why it matters and what new information it should add. This keeps the mode useful for product work, quantitative research, architecture decisions, and other domains without locking it to a fixed taxonomy.

## Cross-Review Gate

First-round workers stay independent. If a high-impact claim appears from one lens or if lenses conflict on a decision-critical action, the claim is recorded with a `target_id`. Pending targets are cross-reviewed in a targeted second round, downgraded as non-decision-critical, or moved to external verification.

Cross-reviewed claims are classified as `accepted`, `modified`, `rejected`, `unresolved`, or `external-verification`.

New runs use the `adaptive-backlog-v1` protocol. New follow-up rounds use 1-6 fresh follow-up workers per batch. Pending targets beyond six remain in a pending backlog. Round 3+ requires approval for each additional batch. Legacy active runs retain fixed-six and Round-4-cap behavior.

`objective_alignment` is a declared semantic judgment, not automated proof. Round JSON is canonical and projections are repaired deterministically. Worker resume is not implemented in this release.

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

Clone the repository directly into Codex's skills directory:

```bash
mkdir -p ~/.codex/skills
git clone https://github.com/smallocean43658/multi-agent-analysis-skill.git ~/.codex/skills/orchestrating-multi-agent-analysis
```

Restart or refresh your Codex session so the skill list is reloaded.

To update an existing install:

```bash
cd ~/.codex/skills/orchestrating-multi-agent-analysis
git pull --ff-only
```

If your Codex environment only scans `~/.agents/skills`, install to that
directory instead, or create one symlink from the Codex install:

```bash
mkdir -p ~/.agents/skills
ln -sfn ~/.codex/skills/orchestrating-multi-agent-analysis ~/.agents/skills/orchestrating-multi-agent-analysis
```

If a session says the skill is not exposed, first verify the local install path:

```bash
test -f ~/.codex/skills/orchestrating-multi-agent-analysis/SKILL.md
```

If the file exists but the skill is still missing from the session's skill list,
restart or refresh Codex. Some runtimes select which skills are exposed per
session; that is separate from whether the files exist on disk.

## Requirements

Local validation requires:

- Python >= 3.10
- Bash >= 4

On macOS, the system `/bin/bash` is often Bash 3.2. Install a newer Bash and run the shell tests with that binary when validating this repository.

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
2. Prepare six Round 1 assignments from the fixed decision chain.
3. Dispatch six Round 1 workers through the active multi-agent tools.
4. Record spawn, result, and close lifecycle events.
5. Write structured synthesis.
6. Stop or prepare a fresh 1-6-worker follow-up batch only if the continuation gate is satisfied.

For new runs, each Round 3+ follow-up batch requires explicit user approval. Legacy active runs retain their fixed-six Round-4 cap.

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
bash tests/test-release-metadata.sh
```

Smoke tests do not exercise live multi-agent tool calls. They validate prompt contracts, helper state transitions, and release metadata. A real analysis run still requires worker-capable tools in the active Codex session.

## License

This repository uses a restricted license. You may use and modify it for personal, internal, or private project use. You may not publish, redistribute, sublicense, sell, package, mirror, host, or otherwise make original or modified copies available to third parties without prior written permission. See `LICENSE`.

## Repository Layout

- `LICENSE`: restricted use license; use and modification are permitted, publishing and redistribution are not.
- `SKILL.md`: the actual Codex skill instructions.
- `round-subagent-prompt.md`: worker prompt template.
- `scripts/run-ledger`: helper for run records and lifecycle validation.
- `test-prompts.json`: prompt contract corpus.
- `tests/test-prompt-contract.py`: validates trigger and mode contracts.
- `tests/test-run-ledger.sh`: validates ledger state transitions.
- `tests/test-release-metadata.sh`: validates public repository metadata and compatibility notes.
- `MAINTENANCE.md`: maintainer notes, change log, verification checklist, and known limits.
