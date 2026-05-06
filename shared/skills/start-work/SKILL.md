---
name: start-work
description: Mandatory protocol when starting implementation after a plan is approved. Enforces worktree creation, staging health check, TDD loop, and commit discipline. Auto-invokes when transitioning from planning to coding.
user-invocable: true
disable-model-invocation: false
effort: high
allowed-tools: Bash(git *) Bash(cargo *) Bash(cd * && bun *) Read Grep Glob Agent
---

# Start Work: Plan-to-Implementation Protocol

You are transitioning from an approved plan to implementation. Follow this protocol exactly. Skipping steps causes merge conflicts, broken staging, and wasted time.

## STOP — Pre-flight Check

Before writing any code, answer these questions:

1. **Is there an approved plan in context?** Resolve via Step 0 below. If none — stop, go back to `/spec` or `/plan`.
2. **Am I in a worktree?** If not — create one (Step 1 below). NEVER implement in the main working tree.
3. **Is staging green?** If not — fix staging first. No work starts on a broken staging.

## Step 0: Locate the approved plan

Two resolution paths, in order — no other heuristics:

1. **Explicit argument** — `/start-work <plan-path>`. Use it directly after verifying the file exists and `Status: APPROVED`.
2. **Conversation context** — look at the current conversation. Is there a single specific plan the operator just discussed (finished `/spec` for it, opened it in `plan-view`, asked a question about it)? If yes — propose it and CONFIRM: `"Starting work on docs/plans/<X>.md. Correct? (yes / no — name the plan you mean)"`. Only proceed on yes.

If neither path is clear — STOP and ask the operator in natural language:
```
Which plan should I implement? Examples:
  - "the dashboard one"
  - "docs/plans/x-api-migration.md"
  - "the spec we just discussed"
```
Then resolve their answer, confirm the match before proceeding. The operator's words are the source of truth; never silently fall back to a filesystem heuristic.

If the resolved plan does not have `Status: APPROVED` — STOP, ask the operator: route to `/spec` / `/review-plan` first, or override explicitly.

Extract from the chosen plan:
- `slug` — filename without `.md` (used as worktree directory + branch suffix)
- `title` — first H1 (used in commit messages and PR title later)

## Step 1: Create Worktree with the plan as first commit

MANDATORY for all feature work. NEVER implement in the main working tree.

### Worktree location, branch naming, and the plan-commit

- **Worktree directory**: `.worktrees/<slug>/` inside the repo root (slug from Step 0).
- **Branch name**: `feat/<slug>` — derived from the plan slug, no random hashes. (For dispatched-to-Linear work this is `<bot>/mag-N-<slug>` instead — that's `/dispatch-to-linear`'s territory; for local /start-work, just `feat/<slug>`.)
- **One agent = one worktree = one branch.** No sharing.
- **The plan is the first commit on the branch.** This way the plan + implementation arrive together in the eventual PR; staging never carries "planned but not implemented" docs.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
SLUG="<slug-from-step-0>"
BRANCH="feat/$SLUG"
WT_PATH="$REPO_ROOT/.worktrees/$SLUG"

# Create the worktree branched off staging, including the plan file
# in working tree (it follows from the staging WT if it was uncommitted
# there during /spec).
mkdir -p "$REPO_ROOT/.worktrees"
git worktree add -b "$BRANCH" "$WT_PATH" staging

cd "$WT_PATH"

# Commit the plan as the first commit. If the plan was already part of
# the worktree (because /spec wrote it before /start-work), it's right
# here. If /spec wrote to staging WT and that WT is dirty, copy/move
# it in first.
if [ ! -f "docs/plans/$SLUG.md" ]; then
  echo "ERROR: docs/plans/$SLUG.md not in worktree — bring it in first"
  exit 1
fi
git add "docs/plans/$SLUG.md"
git commit -m "plan($SLUG): approved spec"
```

**Examples of GOOD branch names**: `feat/dashboard-frontend`, `feat/email-send-fix`, `feat/trigger-gate-mock`.
**Examples of BAD names**: `feat/work`, `task/123`, `.worktrees/worktree-agent-a03de810`.

The `.worktrees/` directory is in `.gitignore` — worktrees are local-only.

If you are already in a worktree (check: `git rev-parse --show-toplevel` differs from main repo root), skip to Step 2 — but verify the plan-commit is already at the head of your branch's history. If not, add it now before any implementation work.

## Step 2: Verify Staging is Green (tiered)

Classify the task before running anything:

- **Trivial** (one file, <50 lines, no new deps): skip preflight entirely. Pre-commit will catch issues.
- **Standard** (one module, one crate, or UI-only): run `cargo check --workspace` + the affected crate's tests only (or `cd frontend && bun run typecheck` for UI-only).
- **Large** (multi-crate, schema, migration, or plan has ≥3 stages): full suite below.

Full suite (Large only):
```bash
# Backend
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Frontend
cd frontend && bun run typecheck && bun run lint && bun run test

# Agent
cd agent && bun run typecheck && bun run test
```

If unsure of classification, treat as Standard. The goal is proving the base compiles and the area you're touching is green — not re-proving the whole repo. If ANY check that you run fails, fix it first.

## Step 3: TDD Loop (for each plan stage)

For each stage in the approved plan, follow this exact loop:

```
1. Write RED test (must FAIL on current code)
   - If the test passes immediately, it doesn't capture the requirement. Rewrite it.

2. Implement the minimum code to make the test GREEN

3. Run full test suite — no regressions

4. Run `/fast-precommit` — scoped to changed files, not the whole workspace.
   - Frontend-only → bun typecheck + lint + test --changed
   - One crate → cargo test -p <crate>
   - Cross-crate / schema / migrations → full workspace fallback
   - Codex review pass only on diffs >200 lines or public-API changes

5. Commit
   - If pre-commit hook fails → fix → commit again
   - NEVER use --no-verify

6. Move to next stage
```

## Step 4: Commit Message Format

Conventional Commits. Include stage number and plan summary.

```
feat(module): description of what this stage implements [Stage N/M]

## Plan: <plan title>
Stage 1: <done marker> <description>
Stage 2: <done marker> <description> (THIS COMMIT)
Stage 3: <description>
...

## Changes in this stage
- <bullet list of what changed>
```

## Step 5: After All Stages Complete

1. Run full verification one more time (backend + frontend + agent) — this is the single full-suite gate for the whole plan.
2. Run `/review-implementation` — self-review gate, SINGLE PASS
   - Round 1: fix blocking items only (missing tests, wrong behavior, security, data loss, public-API break)
   - If still REJECT: one more round, same filter
   - Wording/naming/doc-phrasing comments are OUT OF SCOPE — ignore them or file as follow-up
   - Do NOT loop past round 2
3. Report completion to user with summary
4. **Do NOT merge.** User merges worktree to staging via `git merge`.

## Absolute Prohibitions

- NEVER pick a plan by mtime. Use Step 0 — explicit path, conversation context, or ask the operator.
- NEVER skip the plan-commit on the new branch. The plan must be the first commit; implementation stages stack on top.
- NEVER work in the main tree. If you catch yourself editing files outside a worktree — STOP.
- NEVER merge to staging or main. Only the user does this.
- NEVER use `cp` or `git checkout <branch> -- <files>` to move code between trees.
- NEVER use `--no-verify` to skip pre-commit hooks.
- NEVER skip the RED test phase. The test must fail before you implement.
- NEVER add fallbacks, defaults, or "just in case" code not in the approved plan.
- NEVER stop partway through. Deliver 100% of the plan or explain what blocked you.
- NEVER pause between stages to ask "continue or review?". Stage transitions are AUTOMATIC — start the next stage immediately after the current stage's commit. Stop only on (1) stage failure, (2) plan ambiguity, (3) explicit user interrupt. Each commit is a natural pause point — the user interrupts there if they want.

## If Something Goes Wrong

- Pre-commit hook fails → read the error, fix the issue, commit again
- Test fails unexpectedly → investigate root cause, don't comment out the test
- Staging was broken → fix staging first, then continue feature work
- Plan is ambiguous → ask the user, don't guess

## Task

$ARGUMENTS
