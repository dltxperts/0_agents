# Global Claude Code instructions

This file is the entry point for every Claude Code session — both interactive
sessions on Mac and Cyrus background agent runs on the dev server.

## At the start of any task

1. Detect environment (see "Modes" below).
2. If a project-local CLAUDE.md exists in `$cwd` or any ancestor directory,
   read it. Project rules override global ones for project-specific conflicts.
3. Determine the language(s) the task touches. Read the matching
   `~/.claude/lang/<lang>.md` for each.
4. If the task description contains an "Auto-generated from /spec skill" header
   or an already-structured plan (Decisions, Invariants, Implementation stages),
   DO NOT re-plan. Proceed directly to implementation.

## Modes

You are running in one of two modes. Detect by inspecting your current working
directory.

### Cyrus background mode

**Trigger**: cwd path contains `/.cyrus/worktrees/` (e.g.
`/home/vibe/.cyrus/worktrees/<issue-id>/`, or any user's home).

You are an autonomous background agent processing a Linear-assigned issue.

- DO NOT invoke `/spec`, `/start-work`, `/plan`, `/review-plan`,
  `/review-implementation`, `/quick-fix`, `/dictate`, or any other planning or
  user-interactive skill. The plan is already in the Linear issue. Execute it.
- These skills exist on the filesystem because the human sometimes works
  interactively on this same server via SSH; they are not for you in
  background mode.
- The worktree is created by Cyrus. Don't create another.
- Don't merge to `main` or `staging`. Open the PR and stop.
- You may invoke deterministic utility skills (run tests, format, lint) as
  part of implementation if they exist.

### Interactive mode

**Trigger**: anything else — your cwd is a normal project path, on Mac or on
the server via SSH / VS Code Remote-SSH.

The human is working interactively. All skills are available, including the
planning ones.

## Language routing

Read the matching file for each language the task touches:

- Rust → `~/.claude/lang/rust.md`
- TypeScript / JavaScript / React / Node → `~/.claude/lang/typescript.md`

For multi-language tasks, read all relevant files.

## Always-on principles

### TDD

- Define **invariants** (a numbered list of testable statements) before writing
  any code.
- Write a **RED test** that captures each invariant — it must FAIL on current
  code. If it passes immediately, it doesn't capture the invariant; rewrite it.
- Implement the minimum code to make the test GREEN.
- Run the full suite to verify no regressions before moving to the next stage.

### Commit discipline

- **Conventional Commits**: `feat(scope):`, `fix(scope):`, `refactor(scope):`,
  `test:`, `docs:`, `chore:`.
- Commit only at explicit gates: the user asks for a commit, OR a complete
  stage of an approved plan is finished.
- All changes via PR. **Never push directly to `main` or `staging`.**
- All code changes happen in worktrees. **One agent = one worktree = one
  branch.** Never implement in the main working tree.
- Merge worktrees ONLY via `git merge`. **NEVER `cp`**, **NEVER
  `git checkout <branch> -- <files>`** to move code between trees.
- All checks must pass before merge — zero broken checks. No "pre-existing"
  exceptions.
- **NEVER use `--no-verify`** to skip pre-commit hooks. Fix the hook failure
  instead.

### Code changes

- **Explore before editing.** Don't guess file ownership, architecture, or
  verification requirements. Read relevant files and grep for patterns first.
- **NO FALLBACKS without user confirmation.** Never add fallback logic, default
  behaviors, safety nets, or "just in case" code that wasn't explicitly
  requested. If a value is missing, leave it missing and surface the error.
- When docs and current code differ, **prefer the code** and call out the
  drift to the user.

### Process etiquette

- Don't kill, stop, reuse, or attach to processes you didn't start.
- Don't use shared/main dev ports for E2E or Playwright verification — pick
  isolated ports per worktree.

## Project-local override

If a project's `CLAUDE.md` disagrees with this file on a specific rule, the
project wins for that project. Otherwise this file is the source of truth.

## Boundaries (always)

- Never modify `.github/workflows/`, `infrastructure/`, `.claude/`,
  `~/.claude/`, `~/.cyrus/`, or any path containing secrets, unless the task
  explicitly names the file.
- Never edit `CLAUDE.md` or `AGENTS.md` as part of a feature task. They are
  governance documents — changes to them are a separate task initiated by the
  user.
