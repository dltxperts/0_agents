---
name: review-plan
description: Plan review with strict iterate-until-APPROVED loop and finding triage. After every fix, re-run review; never self-assert. For context-mismatched findings (e.g. security on local-only code), ask the user before applying.
user-invocable: true
disable-model-invocation: true
---

# Plan Review

Review the active plan, triage findings, loop until APPROVED, or escalate
to the user when stuck.

## Rules (do not violate)

- **Re-run review after every fix.** Self-assertion ("fixes addressed the
  findings, should be approved now") is NOT review. Only the most recent
  review output counts as the verdict.
- **Never apply review findings blindly.** Triage every finding (see below).
- **Never exit on NEEDS_WORK.** The loop continues until APPROVED, or
  until the iteration cap forces a human decision.
- **Iteration cap: 3 review rounds.** If after round 3 the review still returns
  NEEDS_WORK, STOP and escalate to the user.

## Triage — every finding goes into one of three buckets

- **REAL** — clear gap, bug, or risk in the plan. APPLY the fix.
- **CONTEXT-MISMATCHED** — the concern doesn't apply given the actual
  context (e.g. security warning for a CLI that runs only on the user's
  local machine, performance concern on a one-shot script, "abstract this"
  on a 5-line helper). ASK THE USER before applying. Do not assume review
  is always right; do not silently skip either.
- **STYLE / WORDING** — naming, phrasing, doc tone, comment style. IGNORE;
  do not re-enter the loop for these.

For each CONTEXT-MISMATCHED finding, present to the user:

```
Review flagged: <quote of the finding>
Looks context-mismatched because: <agent's reasoning, e.g. "the plan
  describes a CLI that runs only locally; no network surface to attack">
Options:
  a) apply fix anyway
  b) skip; add a one-line clarification to the plan so the next round
     doesn't re-raise (e.g. "Note: this binary is local-only, no remote
     attack surface — security review of <area> not applicable")
  c) skip silently (override; risk: review may flag again next round)
How to proceed?
```

Wait for the user's answer per finding before continuing.

## Mechanics

### How to find the plan

1. If plan mode is active, use the active plan path from the conversation.
2. Otherwise, find the most recently modified `docs/plans/*.md` file.

### How to run review

Read the plan file and pass its content directly to the review surface when
needed. Do not create temp copies unless a project-specific tool requires it.

### What review evaluates

Requirements completeness; architecture feasibility; file change map (every
file listed with CREATE / MODIFY); test specification quality (step-by-step
`Step N → Verify` behavioral scenarios, NOT pseudocode); test strategy;
file count justification.

## Loop

```
round = 1
while round ≤ 3:
  run review on the plan content
  if output starts with APPROVED:
    return "APPROVED — review agreed in round N"
  triage findings → REAL / CONTEXT-MISMATCHED / STYLE
  for each REAL: apply fix to plan
  for each CONTEXT-MISMATCHED: ask user, follow their decision
  ignore STYLE
  round += 1

return "NEEDS_HUMAN_DECISION — 3 review rounds exhausted.
  Remaining: <list>
  Asking the user how to proceed."
```

## Output (enum — return one only)

- `APPROVED — review agreed in round N`
- `NEEDS_HUMAN_DECISION — <reason>` (3-round cap hit, or user override
  mid-loop, or all remaining findings are CONTEXT-MISMATCHED)

Never return "fixes applied, should be approved" or "concerns are addressed"
without re-running review.
