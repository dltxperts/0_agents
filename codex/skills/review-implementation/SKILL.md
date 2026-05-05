---
name: review-implementation
description: Post-implementation review gate. Runs tests, launches 3 parallel cop reviews (coherence, coverage, simplicity), runs Codex code review, triages findings (real / context-mismatched / style), and reports a structured verdict. Does NOT fix; pure review. Use after an agent has made code changes.
user-invocable: true
disable-model-invocation: true
effort: high
---

# Review Implementation

Post-implementation review gate. Run after an agent has made code changes.
Verifies tests, enforces project rules via 3 cops, runs Codex code review,
triages all findings, reports a structured verdict.

This skill does NOT fix. The caller (e.g. /start-work, /execute) handles
the fix-and-re-review loop.

## Anti-patterns (do not do)

- **Self-assertion:** "I think the cops would approve now" or "fixes
  addressed the findings" instead of actually running the review. NEVER.
  Run cops, run Codex, report what they say.
- **Skipping re-review after fixes (caller's loop):** caller MUST re-call
  /review-implementation after applying fixes; this skill cannot enforce
  that, but report it explicitly when the caller asks for a single round.
- **Blindly forwarding Codex / cop findings:** triage them first; do not
  treat every finding as REAL.

## Stop conditions (hard)

- **Max 2 review rounds (caller's outer loop).** After round 2, remaining
  comments are filed as follow-up issues, not fixed inline.
- **Wording-only suggestions are OUT OF SCOPE.** Naming, doc phrasing,
  log message text, comment tone — drop them; do not surface.
- Only these comment classes can block APPROVAL when triaged as REAL:
  - Missing or incorrect tests
  - Incorrect behavior vs plan invariants
  - Security issue
  - Data loss risk
  - Public-API break

## Context

You are reviewing changes made by another agent. There may be an active
plan in the conversation — use it to understand intent.

Read AGENTS.md and relevant project docs first for project rules.

## Phase 1: TEST GATE

Run tests for the changed areas.

If `.codex/temp/env.sh` exists, source it and use `$TYPECHECK_CMD`,
`$LINT_CMD`, `$TEST_CMD`. Otherwise detect from project manifests
(package.json → bun, Cargo.toml → cargo, pyproject.toml → pytest, etc.).

- **All tests pass** → proceed to Phase 2.
- **Tests fail** → STOP. Report failures. Do NOT attempt fixes.

## Phase 2: COP REVIEW

Launch the three cops in parallel using the available subagent surface:

- coherence-cop  (`~/.codex/agents/coherence-cop.md`)
- coverage-cop   (`~/.codex/agents/coverage-cop.md`)
- simplicity-cop (`~/.codex/agents/simplicity-cop.md`)

Collect their verdicts and finding lists.

## Phase 3: CODEX CODE REVIEW

Run a Codex code-review pass with a prompt covering correctness, behavior
vs plan invariants, security, data integrity, and API stability. If an MCP
review tool is available, use it; otherwise perform the review locally.

## Phase 4: TRIAGE

For every finding from cops + Codex, classify into one bucket:

- **REAL** — clear gap, bug, or risk in the actual context. Block APPROVAL.
- **CONTEXT-MISMATCHED** — concern doesn't apply given context (e.g.
  security warning on a local-only CLI, "abstract this" on a 5-line
  helper, performance concern on a one-shot script, "add metrics" on a
  prototype). Surface as ASK_USER.
- **STYLE / WORDING** — naming, doc phrasing, log tone. DROP per scope;
  do not surface.

If unsure whether a finding is REAL or CONTEXT-MISMATCHED, default to
CONTEXT-MISMATCHED (ask the user). Better one user question than silently
mis-fixing.

For each ASK_USER, include in the report your reasoning so the user can
decide quickly:

```
ASK_USER: <quote of finding>  [from: <cop name | Codex>]
  Why context-mismatched: <e.g. "the binary runs only on user's local
    machine; no remote attack surface for the security concern raised">
  Options: (a) apply (b) skip with clarification (c) override
```

## Phase 5: FINAL REPORT

Present a consolidated structured verdict:

```
REVIEW VERDICT: [APPROVED | NEEDS_WORK | NEEDS_HUMAN_DECISION]

Tests: PASS

Cops:
  coherence-cop:  [PASS|REJECT] (N findings)
  coverage-cop:   [PASS|REJECT] (N findings)
  simplicity-cop: [PASS|REJECT] (N findings)

Codex: [APPROVED|NEEDS_WORK]

REAL findings (must fix before approval):
  - <finding> — <source>
  ...

ASK_USER findings (context-mismatched; need human decision):
  - <finding> — <source>
    Why context-mismatched: <reasoning>
    Options: (a) apply (b) skip with clarification (c) override
  ...

DROPPED (style/wording, out of scope):
  - <finding> — <source>
  ...
```

VERDICT rules:
- **APPROVED**: no REAL, no ASK_USER. (DROPPED is fine.)
- **NEEDS_WORK**: REAL findings exist; caller must fix.
- **NEEDS_HUMAN_DECISION**: ASK_USER findings exist (regardless of REAL);
  caller must consult user before next round.

Do NOT fix anything. Do NOT return any verdict besides the three above.
No "should be fine now", no "fixes will address" — those are anti-patterns.
