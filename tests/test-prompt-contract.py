#!/usr/bin/env python3
"""Validate prompt-level smoke contracts for the multi-agent analysis skill."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROMPTS_PATH = ROOT / "test-prompts.json"
SKILL_PATH = ROOT / "SKILL.md"

VALID_MODES = {"review", "divergent-analysis"}

REQUIRED_CATEGORIES = {
    "explicit-review-trigger",
    "explicit-divergent-trigger",
    "ordinary-review-non-trigger",
    "ordinary-planning-non-trigger",
    "parallel-workstreams-non-trigger",
    "clarification-before-run",
    "missing-tooling-blocker",
    "tooling-mapping",
    "exactly-six-enforcement",
    "continuation-gate",
    "round3-user-approval",
    "ordinary-divergent-non-trigger",
}

REQUIRED_BEHAVIORS = {
    "create-run-record",
    "six-review-lenses",
    "six-divergent-lenses",
    "wildcard-metadata",
    "dispatch-six-workers",
    "record-results-and-close",
    "ask-clarification-before-run",
    "stop-on-missing-tools",
    "no-fake-workers",
    "record-active-tool-names",
    "no-hardcoded-tooling",
    "require-exactly-six",
    "refuse-partial-round",
    "continuation-gate",
    "round2-only-if-decision-critical",
    "round3-user-approval",
    "round4-cap",
    "no-skill",
}


def fail(message: str) -> None:
    raise SystemExit(message)


def load_prompts() -> list[dict[str, object]]:
    try:
        data = json.loads(PROMPTS_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {PROMPTS_PATH}: {exc}")
    if not isinstance(data, list):
        fail("test-prompts.json must contain a JSON array")
    return data


def assert_prompt_contracts(prompts: list[dict[str, object]]) -> None:
    ids: set[object] = set()
    categories: set[str] = set()
    behaviors: set[str] = set()
    triggered = 0
    not_triggered = 0
    modes: set[str] = set()

    for item in prompts:
        for key in ("id", "scenario", "prompt", "contract", "expected"):
            if key not in item:
                fail(f"prompt item missing {key}: {item!r}")
        if item["id"] in ids:
            fail(f"duplicate prompt id: {item['id']!r}")
        ids.add(item["id"])

        scenario = str(item["scenario"])
        contract = item["contract"]
        if not isinstance(contract, dict):
            fail(f"{scenario}: contract must be an object")
        for key in ("should_trigger", "mode", "category", "required_behaviors"):
            if key not in contract:
                fail(f"{scenario}: contract missing {key}")

        should_trigger = contract["should_trigger"]
        mode = contract["mode"]
        category = contract["category"]
        required_behaviors = contract["required_behaviors"]

        if not isinstance(should_trigger, bool):
            fail(f"{scenario}: contract.should_trigger must be boolean")
        if mode is not None and mode not in VALID_MODES:
            fail(f"{scenario}: contract.mode must be one of {sorted(VALID_MODES)} or null")
        if not isinstance(category, str) or not category:
            fail(f"{scenario}: contract.category must be a non-empty string")
        if not isinstance(required_behaviors, list) or not required_behaviors:
            fail(f"{scenario}: contract.required_behaviors must be a non-empty array")
        if any(not isinstance(behavior, str) or not behavior for behavior in required_behaviors):
            fail(f"{scenario}: every required behavior must be a non-empty string")

        categories.add(category)
        behaviors.update(required_behaviors)

        if should_trigger:
            triggered += 1
            if mode not in VALID_MODES:
                fail(f"{scenario}: triggered prompts must declare review or divergent-analysis mode")
            modes.add(mode)
        else:
            not_triggered += 1
            if mode is not None:
                fail(f"{scenario}: non-trigger prompts must declare null mode")
            if "no-skill" not in required_behaviors:
                fail(f"{scenario}: non-trigger prompts must require no-skill behavior")

    if len(prompts) < 12:
        fail("prompt smoke suite must keep broad coverage; expected at least 12 cases")
    if triggered < 8:
        fail("prompt smoke suite must include at least 8 explicit-trigger cases")
    if not_triggered < 4:
        fail("prompt smoke suite must include at least 4 non-trigger cases")
    if modes != {"review", "divergent-analysis"}:
        fail(f"prompt smoke suite must cover review and divergent-analysis modes, got {sorted(modes)}")
    missing_categories = REQUIRED_CATEGORIES - categories
    if missing_categories:
        fail(f"prompt smoke suite missing categories: {sorted(missing_categories)}")
    missing_behaviors = REQUIRED_BEHAVIORS - behaviors
    if missing_behaviors:
        fail(f"prompt smoke suite missing required behaviors: {sorted(missing_behaviors)}")


def assert_skill_mentions_smoke_test() -> None:
    skill_text = SKILL_PATH.read_text(encoding="utf-8")
    if "tests/test-prompt-contract.py" not in skill_text:
        fail("SKILL.md must document the prompt contract smoke test")
    if "test-prompts.json" not in skill_text:
        fail("SKILL.md must mention test-prompts.json as a maintained contract")


def main() -> int:
    prompts = load_prompts()
    assert_prompt_contracts(prompts)
    assert_skill_mentions_smoke_test()
    print(f"prompt contract smoke suite looks good ({len(prompts)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
