---
name: review-plan
description: Plan review via Codex. Evaluates requirements completeness, architecture feasibility, file change map quality, and test specification quality. Use after writing a plan.
user-invocable: true
disable-model-invocation: true
---

# MCP Plan Review

Call mcp__codex__codex to review the active plan.

**How to find the plan:**
1. If plan mode is active — the path is in the system prompt (e.g. `/Users/mikko/.claude/plans/<name>.md`)
2. Otherwise — find the most recently modified `.md` in `/Users/mikko/.claude/plans/`

**Plan files are in user home (`~/.claude/plans/`), NOT in the repo.** Codex runs in a sandbox rooted at the repo — it CANNOT read files outside the repo.

**Therefore: Read the plan file with the Read tool, then pass its CONTENT directly in the Codex prompt.** Do NOT copy files. Do NOT create temp files. Just read → paste into prompt.

Evaluate: requirements completeness, architecture feasibility, file change map quality (must list every file with CREATE/MODIFY), test specification quality (step-by-step behavioral scenarios in `Step N → Verify` format, NOT pseudocode), test strategy, file count justification.

Output: APPROVED/NEEDS_WORK report.