---
name: plan-view
description: Open completed or updated plan documents from SSH/Zellij with the `plan-view` terminal viewer. Use after creating, updating, finalizing, or presenting a Markdown plan in `docs/plans/*.md`, especially when the user wants the plan opened in a separate pane or mentions frogmouth, frogmouth-tuned, zellij, or plan viewing.
---

# Plan View

After creating, updating, finalizing, or presenting a plan document, open it for the user when `plan-view` is available.

## Canonical Command

Use the canonical plan path:

```bash
plan-view <plan-path>
```

For example:

```bash
plan-view /home/marketing/Coding/magnis-app/docs/plans/analytics-sales-machine.md
```

Inside Zellij, `plan-view` opens a right pane by default. For floating view:

```bash
PLAN_VIEW_PANE=floating plan-view <plan-path>
```

## Workflow

1. Resolve the actual plan file path. Prefer `docs/plans/<topic>.md`.
2. If `command -v plan-view` succeeds, run `plan-view <plan-path>`.
3. If `plan-view` is unavailable, report the exact command the user can run. Do not copy the plan into `.claude/plans`, `.codex/plans`, or temp files.
4. If `plan-view` fails because `zellij action new-pane` cannot write to the runtime socket directory, the Codex profile must include `$XDG_RUNTIME_DIR` in `sandbox_workspace_write.writable_roots`. Ask the user to rerun `~/Coding/0_agents/install-codex.sh` and start a new Codex session.

## Notes

- `plan-view` wraps `frogmouth-tuned` when available, then falls back to `glow`, then `less`.
- Do not use GUI open commands from SSH unless the user explicitly requests them.
- Do not change the plan content just to open it.
