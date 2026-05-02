---
name: quick-fix
description: Lightweight protocol for small, low-risk changes (typos, copy edits, one-line fixes, dependency bumps with no API change). Bypasses start-work preflight and review-implementation. User must invoke explicitly — never auto-invoke.
user-invocable: true
disable-model-invocation: true
---

# Quick fix

For small, low-risk changes where the full `/start-work` machinery is pure overhead.

## Scope

Use ONLY when ALL of these hold:
- One file edited
- ≤10 lines changed
- No new logic, no new abstractions
- No public API change
- No schema/migration change

Typical cases: typo, copy edit, wrong constant, bumping a patch-version dep, fixing a comment or log string.

## Protocol

1. **Worktree**: if currently on `main` or `staging`, create a worktree first (same rule as start-work). Otherwise stay put.
2. **Edit** the file directly.
3. **Run only the directly affected test file**, not the workspace. If there is no existing test for the changed code and the change is cosmetic, no test run is required.
4. **Commit** with `fix:` or `chore:` prefix.
5. Done. No `/plan`, no `/review-implementation`, no Codex round.

## Escape hatch back to start-work

If during the edit you discover:
- The change grows beyond one file or adds logic
- You need a new helper or abstraction
- The test file doesn't exist and the change is not cosmetic

→ STOP. Revert, and restart the task under `/start-work` with a proper plan.

## Task

$ARGUMENTS
