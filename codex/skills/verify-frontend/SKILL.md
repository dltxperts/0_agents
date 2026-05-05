---
name: verify-frontend
description: Frontend verification rules for app-visible changes. Enforces browser-based verification, port isolation, and artifact evidence. Auto-invokes when frontend files are modified.
user-invocable: true
disable-model-invocation: false
paths: frontend/**
---

# Frontend Verification Protocol

App-visible frontend changes MUST be verified in a real browser, not only with
typecheck, build, or unit tests. Prefer the project's Playwright setup when
available.

## Core Rules

1. **If a change is visible in the app — verify it in a browser.**
2. **If you say "fixed in the app" — cite the browser verification artifact.**
3. `typecheck`, `build`, and unit tests are supporting checks only. They do NOT count as UI proof.
4. If Playwright was not run, the completion note must say the fix is **unproven in the app**.

## Port Isolation (CRITICAL)

- **NEVER run browser checks against shared or main dev ports.**
- Use the project's isolated worktree E2E flow when documented.
- Each worktree picks its own ports dynamically. Check with `lsof` before binding.

## Before Playwright Navigation

**MANDATORY pre-flight check** — verify YOUR services respond before opening Playwright:

```bash
test -z "${BE_PORT:-}" || curl -s "http://localhost:$BE_PORT/health" || { echo "YOUR backend is NOT running"; exit 1; }
curl -s "http://localhost:$FE_PORT" >/dev/null || { echo "YOUR frontend is NOT running"; exit 1; }
echo "All YOUR services confirmed — safe to open Playwright"
```

Only after this check passes, navigate Playwright to `http://localhost:$FE_PORT`.

## E2E Test Requirements

- Test data must be clearly isolated and cleaned up by the test.
- All `waitForTimeout` calls must have explanatory comments
- Use project-defined execution modes for regression and evidence runs.

## Worktree E2E Stack

Follow project documentation when present, for example
`docs/worktree-e2e-setup.md` or `docs/testing/e2e-standard.md`.

Quick reference:
1. Create isolated state/database for the worktree.
2. Start required backend/agent/frontend services on non-shared ports.
3. Ensure dependencies are installed inside the worktree when needed.
4. Verify all services are healthy before browser navigation.

## What Counts as Evidence

- Browser run with video or screenshot path — **best evidence**
- Playwright regression run passing — acceptable for CI
- Screenshot from Playwright — acceptable supplement
- "typecheck passes" — NOT evidence of UI correctness
- "I looked at the code" — NOT evidence

## Canonical References

- `docs/testing/policy.md` — testing policy and IDs, when present
- `docs/worktree-e2e-setup.md` — worktree E2E setup guide, when present
- `docs/testing/e2e-standard.md` — E2E testing standard, when present
