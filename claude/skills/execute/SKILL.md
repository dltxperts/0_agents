---
name: execute
description: Hand off a long / overnight task and have it driven to 100% unattended. The strict autonomous-execution harness — takes a plan or a clear directive, sets up a worktree, runs the relentless TDD loop via finish-plan, takes safe defaults (logged) instead of stopping to ask, fixes real bugs found at review ceilings, and commits per stage so an interrupted run resumes cleanly. Invoke for "do this overnight" / "run this and don't stop / don't babysit me".
user-invocable: true
disable-model-invocation: false
effort: high
allowed-tools: Bash Read Grep Glob Edit Write Agent
---

# /execute — overnight autonomous handoff

Someone handed you a long-running task to finish **unattended**. Drive it to done.
This is `finish-plan`'s relentless loop with three sharper calibrations that close
the exact ways agents stop where they shouldn't.

## Setup (once)

1. **Spec.** If an approved plan exists (`docs/plans/<slug>.md`), that is the spec.
   If not, write a short staged plan from the directive, commit it as stage #1, and
   proceed — do NOT stop to get the plan blessed when the directive is clear; record
   assumptions instead.
2. **Worktree + TDD** via `/start-work` (isolated worktree, per-stage commits).
3. Keep a running **ASSUMPTIONS** log — one line per default you took.

## The loop

Delegate to **`/finish-plan`** — do not re-implement it. Per stage:
RED test → minimum implementation → full suite → scoped pre-commit → COMMIT → next
stage automatically. Finish ALL stages, then run the plan's acceptance gates.

## The three calibrations (this is what makes `/execute` "hard")

**1. Safe-default-and-continue** — *fixes the "checkpoint and ask" stop.*
An open decision is NOT a stop if a safe default exists. Take it, log
`ASSUMPTION: <decision> → <default> (why)`, and continue. Stop ONLY if there is no
safe default AND the choice is costly-irreversible (destructive, outward-facing, or
hard-to-undo architecture). "I took a default — let me confirm before the big stage"
is **not** a stop.

**2. Fix-real-at-ceiling** — *fixes deferring real bugs at a review-loop ceiling.*
A review/loop ceiling (e.g. `/review-implementation` round 2) caps NIT loops, not
real bugs. A REAL correctness finding at the ceiling → **FIX it** (RED test → fix →
re-gate); do not punt it to a follow-up or ask whether to fix. Only defer pure
style / doc / naming nits.

**3. Be resumable — the honest answer to "what about a 429?"**
A skill **cannot** retry a model-side 429. When the API rate-limits the turn and the
harness's own backoff-retries are exhausted, the turn just ends — there is no live
agent left to "keep going", so no instruction here can run. The skill's job is
therefore NOT to catch the 429; it is to make a death **cheap** and recovery
**automatic**:
- **Commit after every stage** so an interrupted run loses ≤1 stage. On the next
  invocation, resume from the last `[Stage N]` commit (finish-plan does this) —
  re-running `/execute` simply continues.
- **Keep sub-agent fan-out modest.** Bursts of concurrent agents are a top cause of
  429s; don't spawn 16 when 4 will do.
- **TOOL-level transients** (a Bash/HTTP call inside the turn hits a 429 / network
  blip) — *those* you can and should retry with backoff in-turn.
- **Unattended re-kick after a turn-death is orchestration, not this skill.** For a
  truly hands-off overnight run, wrap the invocation in `/loop` (or a `schedule`
  routine) so a stalled/dead session is re-started and resumes from the last commit.

## The ONLY legitimate stops

1. A stage **genuinely fails** after honest debugging (report what you tried — never
   comment out a test or fake green).
2. A decision with **no safe default AND costly-irreversible** consequences.
3. An **explicit user interrupt**.

Everything else — "this is large / multi-stage", "let me check in / report progress",
"context is getting long", "I should flag scope first" — is **not** a stop. Grind.

## Output

- While running: progress is the per-stage commits + the ASSUMPTIONS log. No prose
  check-ins.
- At the end: **one** completion report — stages done, acceptance criteria met
  (AC-by-AC), assumptions taken, and what (if anything) is genuinely blocked. Then:
  **Do NOT merge — the operator merges.**

## Task

$ARGUMENTS
