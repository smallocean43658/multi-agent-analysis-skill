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

EXPECTED_CASES = {
    1: {
        "scenario": "explicit Chinese review trigger",
        "should_trigger": True,
        "mode": "review",
        "category": "explicit-review-trigger",
        "required_behaviors": {
            "create-run-record",
            "six-review-lenses",
            "dispatch-six-workers",
            "record-results-and-close",
            "synthesize",
            "continuation-gate",
        },
    },
    2: {
        "scenario": "explicit English review trigger",
        "should_trigger": True,
        "mode": "review",
        "category": "explicit-review-trigger",
        "required_behaviors": {"target-in-brief", "six-review-lenses"},
    },
    3: {
        "scenario": "explicit Chinese divergent-analysis trigger",
        "should_trigger": True,
        "mode": "divergent-analysis",
        "category": "explicit-divergent-trigger",
        "required_behaviors": {
            "six-divergent-lenses",
            "wildcard-metadata",
            "no-ad-hoc-brainstorming",
        },
    },
    4: {
        "scenario": "explicit English divergent-analysis trigger",
        "should_trigger": True,
        "mode": "divergent-analysis",
        "category": "explicit-divergent-trigger",
        "required_behaviors": {"create-run-record", "assigned-lens-only"},
    },
    5: {
        "scenario": "ordinary review should not trigger",
        "should_trigger": False,
        "mode": None,
        "category": "ordinary-review-non-trigger",
        "required_behaviors": {"no-skill"},
    },
    6: {
        "scenario": "ordinary planning should not trigger",
        "should_trigger": False,
        "mode": None,
        "category": "ordinary-planning-non-trigger",
        "required_behaviors": {"no-skill"},
    },
    7: {
        "scenario": "parallel execution is not multi-agent analysis",
        "should_trigger": False,
        "mode": None,
        "category": "parallel-workstreams-non-trigger",
        "required_behaviors": {"no-skill"},
    },
    8: {
        "scenario": "unclear target",
        "should_trigger": True,
        "mode": "review",
        "category": "clarification-before-run",
        "required_behaviors": {"ask-clarification-before-run"},
    },
    9: {
        "scenario": "missing multi-agent tools",
        "should_trigger": True,
        "mode": "review",
        "category": "missing-tooling-blocker",
        "required_behaviors": {"stop-on-missing-tools", "no-fake-workers"},
    },
    10: {
        "scenario": "callable tool mapping",
        "should_trigger": True,
        "mode": "review",
        "category": "tooling-mapping",
        "required_behaviors": {"record-active-tool-names", "no-hardcoded-tooling"},
    },
    11: {
        "scenario": "exactly six agents",
        "should_trigger": True,
        "mode": "review",
        "category": "exactly-six-enforcement",
        "required_behaviors": {"require-exactly-six", "refuse-partial-round"},
    },
    12: {
        "scenario": "continuation gate after round one",
        "should_trigger": True,
        "mode": "review",
        "category": "continuation-gate",
        "required_behaviors": {"continuation-gate", "round2-only-if-decision-critical"},
    },
    13: {
        "scenario": "third round approval",
        "should_trigger": True,
        "mode": "review",
        "category": "round3-user-approval",
        "required_behaviors": {"continuation-gate", "round3-user-approval", "round4-cap"},
    },
    14: {
        "scenario": "ordinary English review should not trigger",
        "should_trigger": False,
        "mode": None,
        "category": "ordinary-review-non-trigger",
        "required_behaviors": {"no-skill"},
    },
    15: {
        "scenario": "ordinary divergent exploration should not trigger",
        "should_trigger": False,
        "mode": None,
        "category": "ordinary-divergent-non-trigger",
        "required_behaviors": {"no-skill"},
    },
    16: {
        "scenario": "explicit multi-subagent review trigger without count",
        "should_trigger": True,
        "mode": "review",
        "category": "explicit-review-trigger",
        "required_behaviors": {"require-exactly-six", "six-review-lenses"},
    },
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


def assert_case_bindings(prompts: list[dict[str, object]]) -> None:
    by_id = {item["id"]: item for item in prompts}
    expected_ids = set(EXPECTED_CASES)
    actual_ids = set(by_id)
    if actual_ids != expected_ids:
        fail(
            "prompt smoke suite ids changed; "
            f"missing={sorted(expected_ids - actual_ids)} extra={sorted(actual_ids - expected_ids)}"
        )

    for case_id, expected in EXPECTED_CASES.items():
        item = by_id[case_id]
        if item["scenario"] != expected["scenario"]:
            fail(f"case {case_id}: scenario changed from {expected['scenario']!r}")
        contract = item["contract"]
        if not isinstance(contract, dict):
            fail(f"case {case_id}: contract must be an object")
        for key in ("should_trigger", "mode", "category"):
            if contract.get(key) != expected[key]:
                fail(
                    f"case {case_id}: contract.{key} expected {expected[key]!r}, "
                    f"got {contract.get(key)!r}"
                )
        actual_behaviors = set(contract.get("required_behaviors", []))
        if actual_behaviors != expected["required_behaviors"]:
            fail(
                f"case {case_id}: required behaviors expected "
                f"{sorted(expected['required_behaviors'])}, got {sorted(actual_behaviors)}"
            )


def assert_skill_mentions_smoke_test() -> None:
    skill_text = SKILL_PATH.read_text(encoding="utf-8")
    if "tests/test-prompt-contract.py" not in skill_text:
        fail("SKILL.md must document the prompt contract smoke test")
    if "test-prompts.json" not in skill_text:
        fail("SKILL.md must mention test-prompts.json as a maintained contract")


def main() -> int:
    prompts = load_prompts()
    assert_prompt_contracts(prompts)
    assert_case_bindings(prompts)
    assert_skill_mentions_smoke_test()
    print(f"prompt contract smoke suite looks good ({len(prompts)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
