---
name: completion-note
description: Completion note format and verification matrix. Use when finishing a task to produce a structured report of what changed, what was tested, and what remains unverified. Auto-invokes when reporting task completion.
user-invocable: true
disable-model-invocation: false
---

# Completion Note Protocol

Every task completion must include a structured report. Do not present partial verification as final proof.

## Required Sections

### 1. What Changed

List files modified/created, grouped by layer. Be specific — not "updated backend" but "added `sync_coverage` method to `SyncService`".

### 2. Tests Added/Updated

List numbered test IDs (`tst_*`) and scenarios (`scn_*`) that were added, updated, or relied upon. If no tests were added — explain why.

### 3. Commands Run

List the exact verification commands that were executed and their results:

```
cargo fmt --all --check          OK
cargo clippy -- -D warnings      OK
cargo test --workspace           OK (N tests passed)
cd frontend && bun run typecheck OK
cd frontend && bun run lint      OK
cd frontend && bun run test      OK (N tests passed)
```

### 4. Playwright Evidence (for app-visible changes)

- Was Playwright run? Yes/No
- If yes: execution mode (`showcase` / `regression`), video path
- If no: explicitly state the fix is **unproven in the app**

### 5. Unverified Risks

List anything that was NOT tested or verified. Be honest — hidden risk is worse than acknowledged risk.

## Verification Matrix

Use the correct verification level based on what changed:

| Change Type | Required Verification |
|-------------|----------------------|
| Backend / domain logic | Invariants defined, numbered tests added, `cargo fmt + clippy + test` |
| Backend integration / sync | TestCore or mock-runtime coverage, no live providers |
| Frontend non-visual logic | `bun typecheck + lint + test`, but NOT presented as UI proof |
| Frontend app-visible | **Playwright required**; typecheck/build are supporting only |
| Agent / policy path | Approval gates, allowlists, MCP path correctness verified |

## Anti-patterns (DO NOT)

- "All tests pass" without listing which tests
- "Fixed in the app" without Playwright evidence
- "Typecheck passes" as proof of UI correctness
- Omitting unverified risks to make the report look clean
- Claiming completion when implementation is partial

## Template

```
## Completion Note

### What changed
- <file>: <description>

### Tests
- tst_*: <description> (added/updated/relied upon)
- scn_*: <description>

### Verification
<command>  <result>
...

### Playwright
<ran/not ran> — <mode> — <video path or "unproven in app">

### Unverified risks
- <risk or "none identified">
```
