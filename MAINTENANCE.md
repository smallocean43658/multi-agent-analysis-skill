# Maintenance Notes

This file is for maintainers. Keep user-facing explanation in `README.md` and runtime protocol in `SKILL.md`.

## Repository Status

- Repository: `https://github.com/smallocean43658/multi-agent-analysis-skill.git`
- Main branch: `main`
- Local run records: `.superpowers/` and `.darwin/`, ignored by git

## Compatibility

- Python >= 3.10
- Bash >= 4
- macOS users may need a newer Bash than the system `/bin/bash` to run `tests/test-run-ledger.sh`.
- Smoke tests do not exercise live multi-agent tool calls; real dispatch requires worker-capable tools in the active Codex session.

## Design Decisions

- This skill is independent from the Codex superpowers skill. It has its own repository, workspace, git history, and run records.
- `SKILL.md` is the runtime authority for agents.
- `README.md` is the user-facing introduction, value explanation, installation guide, and usage entrypoint.
- `MAINTENANCE.md` is the maintainer-facing record. Do not move maintenance history into README.
- `LICENSE` permits use and modification but prohibits publishing, redistribution, sublicensing, sale, packaging, mirroring, hosting, or third-party availability without prior written permission.
- `scripts/run-ledger` owns mechanical validation, lifecycle state transitions, and markdown rendering.
- The main agent still owns judgment: whether to trigger, which active tools to use, how to synthesize, and whether another round is worth running.
- Round 1 and legacy protocol rounds use six workers; adaptive follow-up batches use 1-6.

## Change Log

### 2026-07-11

- New review-run decision-chain version: `decision-chain-b1-b6-v1`.
- Public review contract: B1-B6 with the documented engineering overlay.
- `adaptive-backlog-v1` decision: new follow-up batches use 1-6 fresh workers and retain pending targets in the backlog.
- Fresh-only activation decision: every follow-up worker is newly activated; worker reuse is not implemented.
- Canonical-round reconciliation decision: round JSON is canonical and projections reconcile deterministically.
- Legacy compatibility behavior: active legacy runs retain fixed-six and Round-4-cap behavior.
- Deferred to a separate evidence-backed plan: worker resume, replacement, retry, and multi-activation.
- Validation commands:
  - `bash tests/test-release-metadata.sh`
  - `python3 tests/test-prompt-contract.py`
  - `bash tests/test-run-ledger.sh`
  - `bash tests/test-ledger-recovery.sh`
  - `bash tests/test-followup-protocol.sh`
  - `bash -n tests/test-ledger-recovery.sh`
  - `bash -n tests/test-followup-protocol.sh`

### 2026-07-04

- Changed divergent-analysis round-one lenses from fixed categories to target-adaptive lenses.
- Preserved explicit multi-agent wording as the trigger precondition; ordinary analysis requests remain non-triggers.
- Added claim-level `target_id` tracking for Cross-Review Gate targets and outcomes.
- Added markdown rendering expectations for cross-review gate state, targets, and outcomes.
- Hardened Cross-Review Gate finalization invariants:
  - pending targets require `cross_review_gate_status: needs_cross_review` and `continue_round_2`
  - `needs_cross_review` requires at least one pending target
  - targeted cross-review rounds require `C1` through `C6`
  - round-two outcomes reject missing or extra `target_id` values
  - unresolved or externally verified outcomes cannot be finalized under the wrong gate state
- Added the implementation plan under `docs/superpowers/plans/2026-07-04-adaptive-divergent-cross-review.md`.
- Final independent review found no Critical or Important issues after the pending-target invariant fix; remaining note is a non-blocking coverage gap for `needs_cross_review` with zero pending targets.

### 2026-07-03

- Created the independent `multi-agent-analysis-skill` repository.
- Added `orchestrating-multi-agent-analysis` as a local Codex skill.
- Added review mode and divergent-analysis mode.
- Added fixed first-round lenses for review mode.
- Added fixed divergent slots plus constrained wildcard metadata for divergent-analysis mode.
- Added `scripts/run-ledger` for durable local run records.
- Added prompt contract smoke tests in `test-prompts.json` and `tests/test-prompt-contract.py`.
- Hardened lifecycle handling:
  - blank tool names are rejected during init
  - lifecycle statuses are strict enums
  - only `completed` results count as usable
  - failed results cannot satisfy normal finalization
  - abnormal close can be recorded as `failed` or `cancelled`
  - blocked finalization is rejected while spawned workers are still open
  - blocked runs cannot prepare another round
  - complete rounds require non-empty synthesis before normal finalization
- Added `record-synthesis` so structured synthesis can be recorded through the helper and rendered into `round-N.md`.
- Split documentation:
  - `README.md` for value, installation, usage, and validation
  - `MAINTENANCE.md` for maintainer notes and change history
- Added a restricted `LICENSE` that allows use and modification but does not grant publishing or redistribution rights.
- Hardened release-readiness blockers:
  - terminal runs and rounds reject later lifecycle mutation
  - already finalized or blocked rounds cannot be finalized again
  - `record-synthesis` requires six completed results and six normal closes
  - blocked finalization requires recorded lifecycle failure evidence
  - `finalize-round` validates decision values against the current round
  - `status` ignores sidecar files such as synthesis payload JSON

## Verification

Run before committing changes:

```bash
python3 tests/test-prompt-contract.py
bash tests/test-run-ledger.sh
bash tests/test-ledger-recovery.sh
bash tests/test-followup-protocol.sh
bash tests/test-release-metadata.sh
python3 -m py_compile scripts/run-ledger tests/test-prompt-contract.py
bash -n tests/test-run-ledger.sh
bash -n tests/test-ledger-recovery.sh
bash -n tests/test-followup-protocol.sh
bash -n tests/test-release-metadata.sh
git diff --check
```

Remove generated `__pycache__/` directories before committing after Python compilation checks.

## Release Checklist

Before pushing to `main`:

- Run the verification commands above.
- Confirm `git status --short` contains only intentional tracked files.
- Confirm `.superpowers/`, `.darwin/`, `__pycache__/`, and `*.pyc` are not staged.
- Confirm `LICENSE` still matches the intended restricted use/no-publishing policy.
- Confirm `README.md` still explains installation and usage without becoming a maintenance log.
- Confirm `SKILL.md` still describes the live runtime protocol.
- Confirm `MAINTENANCE.md` records maintainer-only context and change history.

## Known Limits

- The helper can reject blank tool names, but it cannot prove a recorded tool name is callable in the current Codex session. The main agent must inspect the active tools list.
- The smoke tests validate prompt contracts and ledger state transitions. They do not run real multi-agent tool calls.
- Local run records under `.superpowers/` are intentionally not committed; they are operational evidence, not repository documentation.
- The continuation gate is partly judgment-based. Tests protect caps and approval requirements, but they cannot fully validate synthesis quality.
