#!/usr/bin/env python3
"""Validate prompt-level smoke contracts for the multi-agent analysis skill."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROMPTS_PATH = ROOT / "test-prompts.json"
SKILL_PATH = ROOT / "SKILL.md"
WORKER_PROMPT_PATH = ROOT / "round-subagent-prompt.md"
VALID_MODES = {"review", "divergent-analysis"}
EXPECTED_PROMPT_IDS = set(range(1, 26))

REVIEW_DIMENSIONS = [
    (
        "B1",
        "Goal And Requirement Alignment",
        "Objective, audience, requirements, constraints, and completion evidence",
        "First-principles purpose and requirement analysis",
    ),
    (
        "B2",
        "Mechanism And Structural Validity",
        "Causal mechanism, structural boundaries, and simplest sufficient design",
        "First principles plus Occam's Razor",
    ),
    (
        "B3",
        "Evidence And Uncertainty Audit",
        "Evidence, assumptions, falsifiability, confidence, and missing information",
        "Bounded Bayesian reasoning",
    ),
    (
        "B4",
        "Alternatives And Decision Value",
        "Realistic alternatives, benefit, cost, reversibility, and opportunity cost",
        "Expected-cost and information-value reasoning",
    ),
    (
        "B5",
        "Risk And Robustness",
        "Edge cases, incentives, misuse, hostile conditions, brittle dependencies, degradation, and recovery",
        "Adversarial review",
    ),
    (
        "B6",
        "Execution And Lifecycle",
        "Implementation, testing, operation, migration, maintenance, ownership, and handoff",
        "Execution-friction and lifecycle analysis",
    ),
]

REVIEW_BOUNDARIES = [
    "B1 does not select architecture or implementation sequence.",
    "B2 does not assess business return, enumerate operational attacks, or create delivery schedules.",
    "B3 does not redesign the proposal except to identify evidence-producing tests.",
    "B4 does not own implementation details.",
    "B5 owns abnormal and adversarial failure, not routine project management.",
    "B6 owns normal delivery and lifecycle work, not speculative abuse analysis.",
]

ENGINEERING_OVERLAY_CHECKS = {
    "B1": (
        "functional-requirements",
        "non-functional-requirements",
        "acceptance-criteria",
        "compatibility-and-platform-constraints",
    ),
    "B2": (
        "simplest-sufficient-mechanism",
        "architecture-and-ownership-boundaries",
        "interfaces-data-flow-and-state",
        "dependency-necessity",
    ),
    "B3": (
        "prototype-test-and-benchmark-evidence",
        "technical-assumptions",
        "missing-evidence",
        "falsification-conditions",
    ),
    "B4": (
        "build-buy-and-alternative-architecture",
        "implementation-and-operating-cost",
        "migration-and-switching-cost",
        "reversibility-and-opportunity-cost",
    ),
    "B5": (
        "concurrency-and-data-integrity",
        "security-and-abuse",
        "dependency-and-capacity-failure",
        "degradation-recovery-and-rollback",
    ),
    "B6": (
        "implementation-sequence-and-ownership",
        "test-strategy-and-observability",
        "deployment-and-migration",
        "maintenance-and-handoff",
    ),
}

REQUIRED_CATEGORIES = {
    "explicit-review-trigger",
    "explicit-divergent-trigger",
    "explicit-generic-analysis-trigger",
    "ordinary-review-non-trigger",
    "ordinary-planning-non-trigger",
    "ordinary-analysis-non-trigger",
    "parallel-workstreams-non-trigger",
    "clarification-before-run",
    "missing-tooling-blocker",
    "tooling-mapping",
    "adaptive-divergent-lenses",
    "cross-review-gate",
    "exactly-six-enforcement",
    "continuation-gate",
    "legacy-round4-cap",
    "ordinary-divergent-non-trigger",
    "target-overlay",
    "single-divergent-engineering-angle",
    "no-forced-engineering-overlay",
    "adaptive-followup-backlog",
}

REQUIRED_BEHAVIORS = {
    "create-run-record",
    "six-review-lenses",
    "six-divergent-lenses",
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
    "default-review-uses-B-decision-chain",
    "same-target-boundary",
    "dispatch-six-workers",
    "record-results-and-close",
    "synthesize",
    "target-in-brief",
    "assigned-lens-only",
    "no-ad-hoc-brainstorming",
    "ask-clarification-before-run",
    "stop-on-missing-tools",
    "no-fake-workers",
    "record-active-tool-names",
    "no-hardcoded-tooling",
    "require-exactly-six",
    "refuse-partial-round",
    "continuation-gate",
    "round2-only-if-decision-critical",
    "round3-plus-user-approval",
    "legacy-round4-cap",
    "distributed-engineering-overlay",
    "single-divergent-engineering-angle",
    "no-forced-engineering-overlay",
    "adaptive-followup-backlog",
    "objective-alignment",
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
    unknown_categories = categories - REQUIRED_CATEGORIES
    if unknown_categories:
        fail(f"prompt smoke suite has unknown categories: {sorted(unknown_categories)}")
    missing_behaviors = REQUIRED_BEHAVIORS - behaviors
    if missing_behaviors:
        fail(f"prompt smoke suite missing required behaviors: {sorted(missing_behaviors)}")
    unknown_behaviors = behaviors - REQUIRED_BEHAVIORS
    if unknown_behaviors:
        fail(f"prompt smoke suite has unknown required behaviors: {sorted(unknown_behaviors)}")
    actual_ids = set(ids)
    expected_ids = EXPECTED_PROMPT_IDS
    if actual_ids != expected_ids:
        fail(
            "prompt smoke suite ids changed; "
            f"missing={sorted(expected_ids - actual_ids)} extra={sorted(actual_ids - expected_ids)}"
        )


def assert_skill_mentions_smoke_test() -> None:
    skill_text = SKILL_PATH.read_text(encoding="utf-8")
    if "Root: `multi-agent-analysis/`" not in skill_text:
        fail("SKILL.md must use multi-agent-analysis/ as the local run-record root")
    if ".superpowers/multi-agent-analysis" in skill_text:
        fail("SKILL.md must not use the legacy .superpowers parent for new run records")
    required_skill_terms = [
        "explicit multi-agent",
        "target-adaptive",
        "Cross-Review Gate",
        "target_id",
        "downgraded_non_decision_critical",
        "external-verification",
        "external_verification",
        "same target",
        "analysis` or `分析` alone is not enough",
        "Target overlay",
        "distributed engineering overlay",
        "engineering-feasibility",
        "objective alignment",
        "adaptive backlog",
        "Legacy runs without `protocol_version`",
    ]
    for term in required_skill_terms:
        if term not in skill_text:
            fail(f"SKILL.md must document {term!r}")

    for slot, dimension, responsibility, method in REVIEW_DIMENSIONS:
        expected_row = f"| {slot} | {dimension} | {responsibility} | {method} |"
        if expected_row not in skill_text:
            fail(f"SKILL.md must document exact B1-B6 row: {expected_row!r}")

    for boundary in REVIEW_BOUNDARIES:
        if boundary not in skill_text:
            fail(f"SKILL.md must document B1-B6 boundary: {boundary!r}")

    for slot, checks in ENGINEERING_OVERLAY_CHECKS.items():
        expected_overlay = f"- {slot}: " + ", ".join(f"`{check}`" for check in checks) + "."
        if expected_overlay not in skill_text:
            fail(f"SKILL.md must document exact B-slot engineering overlay: {expected_overlay!r}")

    review_table = re.findall(
        r"\| B1 \| Goal And Requirement Alignment \|[\s\S]*?\| B6 \| Execution And Lifecycle \|",
        skill_text,
    )
    if len(review_table) != 1:
        fail("SKILL.md must contain exactly one complete B1-B6 review table")

    if re.search(r"\| A[1-6] \|", skill_text) or "A1-A6" in skill_text:
        fail("SKILL.md public review guidance must expose B1-B6 only")

    if not re.search(
        r"cross_review_gate_status[\s\S]{0,120}external_verification",
        skill_text,
    ):
        fail(
            "SKILL.md must include `cross_review_gate_status` with `external_verification` "
            "for external-verification outcomes"
        )


def assert_worker_prompt_mentions_contract() -> None:
    prompt_text = WORKER_PROMPT_PATH.read_text(encoding="utf-8")
    required_terms = [
        "B1-B6",
        "D1-D6",
        "C1-C6",
        "why_material",
        "expected_new_information",
        "target_id",
        "claim",
        "accepted",
        "modified",
        "rejected",
        "unresolved",
        "external-verification",
        "Target overlay:",
        "Overlay checks:",
        "Owned lens or dimension:",
        "Out of scope:",
    ]
    for term in required_terms:
        if term not in prompt_text:
            fail(f"round-subagent-prompt.md must document {term!r}")

    if "source_claim" in prompt_text:
        fail("round-subagent-prompt.md must use `claim` instead of `source_claim`")

    if "Return for B1-B6 and D1-D6" not in prompt_text:
        fail(
            "round-subagent-prompt.md must explicitly define broad return contract for "
            "B1-B6/D1-D6 and not reuse the same contract for C1-C6"
        )

    if "Return for C1-C6" not in prompt_text:
        fail(
            "round-subagent-prompt.md must include a dedicated minimal return contract "
            "for C1-C6 targeted cross-review"
        )

    for slot, dimension, _, _ in REVIEW_DIMENSIONS:
        if f"- {slot} {dimension}:" not in prompt_text:
            fail(f"round-subagent-prompt.md must define B-slot lens guidance for {slot}")

    for boundary in REVIEW_BOUNDARIES:
        if boundary not in prompt_text:
            fail(f"round-subagent-prompt.md must state B-slot boundary: {boundary!r}")

    if "A1-A6" in prompt_text:
        fail("round-subagent-prompt.md public review guidance must expose B1-B6 only")

def main() -> int:
    prompts = load_prompts()
    assert_prompt_contracts(prompts)
    assert_skill_mentions_smoke_test()
    assert_worker_prompt_mentions_contract()
    print(f"prompt contract smoke suite looks good ({len(prompts)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
