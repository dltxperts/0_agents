---
name: cleanup-worktrees
description: Prune stale git worktrees. Removes worktrees whose branch is merged to the integration branch OR whose on-disk directory is gone OR whose HEAD is older than 14 days. Safe — never touches active branches or ones with uncommitted work.
user-invocable: true
disable-model-invocation: true
---

# Cleanup worktrees

Clean stale worktrees from the current repository. This is a two-step skill:
first produce a dry-run plan, then act only after explicit approval.

## Protocol

1. Run `git worktree list --porcelain` and parse.
2. For each worktree other than the main one:
   - Get branch, HEAD SHA, last-commit age, locked status.
   - Classify:
     - **prunable**: directory missing on disk (`git worktree prune` will drop it)
     - **merged**: branch is fully merged into the integration branch AND working tree is clean
     - **stale**: last commit older than 14 days AND branch not merged but has no uncommitted changes AND is named `worktree-agent-*` (auto-generated)
     - **keep**: everything else — active work
3. Show the user the plan (one line per worktree, classification, proposed action).
4. Wait for approval.
5. On approval:
   - `git worktree prune` for missing dirs
   - `git worktree remove <path>` for merged/stale, then `git branch -d <branch>`
   - For locked worktrees with auto-generated names: `git worktree unlock <path>` first, then remove

## Safety rules

- NEVER touch the main or integration working directories.
- NEVER remove a worktree with uncommitted changes — report it and skip.
- NEVER `branch -D` (force) — use `-d` and let git refuse if unmerged.
- Show the plan FIRST, act only after user says yes.

## Usage

```
/cleanup-worktrees           # dry-run — show plan, do not touch
/cleanup-worktrees --apply   # perform the pruning after confirmation
```

## Task

$ARGUMENTS
