---
name: git
description: Git workflow policy — branching, commits, merges, history hygiene. Auto-invokes when the task involves any git operation (commit, branch, merge, PR open, history inspection). The defining principle: history is project memory; never rewrite it.
user-invocable: true
disable-model-invocation: false
---

# Git workflow

History is project memory. Never rewrite it. Cleanup happens through good
commit messages, not through history surgery.

## Branching

- Feature work happens in worktrees on dedicated branches.
- Branch naming: `feat/<topic>`, `fix/<topic>`, `refactor/<topic>`,
  `chore/<topic>`, `task/<id>-<topic>`.
- One agent = one worktree = one branch. Never share.
- Base feature branches off `staging` (not `main`) by default.

## Commits

### When to commit

- After each completed stage of an approved plan.
- When the user explicitly asks for a commit.
- When stepping away from in-progress work that you want to preserve as a
  recovery point — wip commits are valid and encouraged.

### Commit messages as project memory

Every commit message explains **why**, not just **what**. The diff already
shows what changed; the message exists to capture intent and context for
future sessions — yours, the agent's, anyone debugging months later.

For wip / exploratory commits this matters even more. They capture
abandoned approaches, failed attempts, and reasoning that led to the
final solution. Future sessions will `git log --grep` for similar
problems.

```
useless:    wip: try something
useful:     wip(auth): try bcrypt hashing — async issue in handler

useless:    fix
useful:     fix(auth): bcrypt needs spawn_blocking, sync hash blocked tokio
```

### Conventional Commits

Use Conventional Commit prefixes consistently:

- `feat(scope): ...` — new functionality
- `fix(scope): ...` — bug fix
- `refactor(scope): ...` — non-behavior-changing restructure
- `test: ...` — tests only
- `docs: ...` — documentation only
- `chore: ...` — tooling, deps, repo config
- `wip(scope): ...` — work in progress, expected to be followed up

Imperative mood ("add login" not "added login"). First character lowercase.
Subject under ~72 characters.

### Body when needed

For non-trivial commits, include a body:

```
fix(sync): handle empty page tokens in Gmail history API

Empty `historyId` from Gmail means "no changes since last sync", not "start
over". Was treating empty as null and refetching everything, blowing through
quota.

Repro: account with no incoming mail for 7 days → forced full resync.
```

The body explains the *why* the subject hints at.

## Merges

### Merge strategy

We use **merge commits**, not squash, not rebase-merge. History is the
project's memory; squashing destroys it.

| Direction              | Method        | Who does it           |
|------------------------|---------------|------------------------|
| feat/* → staging (PR)  | Merge commit  | User after review      |
| staging → main         | Merge commit  | User manually          |

Allowed merge methods in branch protection: **Merge** only. Squash and
Rebase are disabled at the repo level. If the user explicitly asks for a
squash on a specific PR (rare, for genuinely no-information wip chains),
they do it manually in the GitHub UI.

### Never rewrite history

These operations are forbidden in agent work:

- `git rebase` (interactive or otherwise)
- `git commit --amend`
- `git push --force` or `git push --force-with-lease`
- `git filter-branch`, `git filter-repo`
- Resetting public branches
- Squashing commits before opening a PR

If a wip chain looks messy, leave it messy. The mess is the record of how
the work happened.

Exception: if the user explicitly says "rewrite this", do it under their
direction. Default is never.

## PR opening

Before opening a PR:

1. Verify the branch is up to date with the target (e.g. `staging`):
       git fetch origin
       git log staging..HEAD --oneline
   The agent reads, the agent does NOT rebase. If the branch is far
   behind, surface to the user — they decide whether to merge target in
   or wait.
2. Run the verification matrix (see completion-note.md).
3. Push the feature branch.
4. Open the PR with:
   - Title: Conventional Commit format, will become the merge commit
     subject (`feat(auth): add login flow`).
   - Description: structured per template below.

### PR description template

```
## What
<one paragraph: the change in plain English>

## Why
<one paragraph: motivation, link to Linear issue>

## How
<list of stages or major changes, each linked to a commit if helpful>

## Verification
<output of /verify or completion-note style report>

## Visual proof (frontend changes only)
<screenshots or links to Linear attachments>

## Reviewer checklist
- [ ] Behavior matches the spec
- [ ] Tests cover invariants
- [ ] No fallback/default code added
- [ ] No history rewriting in commits
```

## Inspection (when researching how something was done before)

These are encouraged. Use them.

```
git log --oneline --all              # see the full graph
git log --grep "<keyword>"           # find commits by message content
git log -S "<code string>"           # find commits that changed a string
git log -p path/to/file              # full history of a file
git blame path/to/file               # who/when changed each line
git show <sha>                       # full diff + message of a commit
```

When implementing something that resembles past work, search history
first. The previous attempt's wip chain often shows what didn't work and
why — that's exactly the context you need.

## Boundaries

- Never push to `main` or `staging` directly. Only via PR (for staging) or
  manual merge by the user (for main).
- Never delete branches you didn't create. The user controls cleanup.
- Never use `git checkout <branch> -- <files>` to move code between trees.
  That's not a merge, it's a silent overwrite.
- Never use `cp` to move code between worktrees. Same reason.
