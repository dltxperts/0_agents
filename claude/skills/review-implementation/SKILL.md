---
name: review-implementation
description: Post-implementation review gate. Runs tests, launches 3 parallel cop reviews (coherence, coverage, simplicity), then Codex code review. Use after an agent has made code changes.
user-invocable: true
disable-model-invocation: true
effort: high
---

# Review Implementation

Post-implementation review gate. Run this after an agent has made code changes.
Verifies tests, enforces project rules via 3 cops, then runs Codex code review.

## Stop conditions (hard)

- **Max 2 review rounds.** After round 2, any remaining comments must be filed as follow-up issues, not fixed inline.
- **Wording-only suggestions are OUT OF SCOPE.** Naming, doc phrasing, log message text, comment tone — ignore them. Do not re-enter the loop for these.
- Only these comment classes block APPROVAL:
  - Missing or incorrect tests
  - Incorrect behavior vs plan invariants
  - Security issue
  - Data loss risk
  - Public-API break
- If all remaining comments are wording/style → APPROVE with a note listing them.

## Context

You are reviewing changes made by another agent. There may be an active plan in the conversation — use it to understand what was intended.

Read CLAUDE.md and AGENTS.md first for project rules.

## Phase 1: TEST GATE

Run tests for the changed areas. Determine what changed and run the appropriate test suite.

**If backend changes exist:**
```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

**If frontend changes exist:**
```bash
cd frontend && bun run typecheck
cd frontend && bun test
cd frontend && bun run lint
```

- **All tests pass** -> proceed to Phase 2
- **Tests fail** -> STOP. Report failures. Do NOT attempt fixes.

## Phase 2: COP REVIEW

Launch all 3 cops as parallel subagents using `.claude/agents/coherence-cop.md`, `.claude/agents/coverage-cop.md`, `.claude/agents/simplicity-cop.md`.

## Phase 3: CODEX CODE REVIEW

Call `mcp__codex__codex` with review prompt.

## Phase 4: FINAL REPORT

Present consolidated APPROVED/NEEDS_WORK report. Do NOT fix anything — this is a review gate.
