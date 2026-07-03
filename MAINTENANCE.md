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
- Exactly six workers are required for a valid skill round. Partial rounds must stop or be explicitly marked blocked.

## Change Log

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
bash tests/test-release-metadata.sh
bash -n tests/test-run-ledger.sh
git diff --check
```

Run `python3 -m py_compile scripts/run-ledger tests/test-prompt-contract.py` when touching Python code, then remove generated `__pycache__/` directories before committing.

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
