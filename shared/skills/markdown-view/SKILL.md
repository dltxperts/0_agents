---
name: markdown-view
description: Display a markdown file in a separate Zellij pane via `markdown-view <path>` (frogmouth → glow → less fallback chain). Use whenever the operator wants to view a markdown document and you're inside Zellij — plans, SKILL.md files, READMEs, generated docs, anything markdown. Prefer this over pasting long markdown into chat. Auto-invoke after writing or updating any `docs/plans/*.md`, after writing any `SKILL.md`, or when the operator asks to see a markdown file by path.
---

# Markdown View

Open a markdown file in a separate readable pane instead of dumping the content into chat. Works for any `.md` file — plans, skill definitions, READMEs, project docs.

## When to use

**Auto-invoke** when:
- You just wrote or updated a `docs/plans/<slug>.md` plan and want to show it to the operator
- You just wrote or updated a `SKILL.md` and want the operator to review it
- The operator asks "show me X.md" / "посмотрим Y" / "open the plan" / similar
- You're about to paste >40 lines of markdown into chat AND `$ZELLIJ` is set

**Skip** when:
- The file isn't markdown
- You're outside Zellij AND the operator wants to read in their existing terminal anyway
- The markdown is short enough that inline chat display is just as good (≤30 lines)

## Canonical command

```bash
markdown-view <path>
```

Examples:
```bash
markdown-view docs/plans/dashboard-frontend.md
markdown-view ~/.claude/skills/dispatch-to-linear/SKILL.md
markdown-view README.md
```

Inside Zellij the file opens in a right-split pane by default. For floating:

```bash
MARKDOWN_VIEW_PANE=floating markdown-view <path>
```

(Backward-compat: `PLAN_VIEW_PANE` env var still works.)

Outside Zellij the viewer runs inline in the current terminal.

## Fallback chain

The script picks the best available viewer in order:
1. `frogmouth-tuned` — TUI markdown browser (if installed via pipx). Best UX.
2. `glow -p` — pretty-printed terminal renderer. Good fallback.
3. `less -R` — last resort, raw text with ANSI passthrough.

If you only have `less`, the file still opens — just unstyled.

## Workflow

1. Resolve the markdown path. Use absolute paths when the cwd may not be the repo root (zellij panes can have different cwds).
2. Check `command -v markdown-view`. If absent, tell the operator to run `bash ~/Coding/0_agents/install-bin.sh` to install it. Don't paste the file contents as a fallback — they asked for a viewer.
3. Invoke `markdown-view <path>`.
4. Confirm with the operator: announce which file was opened and which pane it's in (e.g. "opened in `terminal_56`").

## On failures

- **`zellij action new-pane` fails with permission/socket error** — the Codex (or Claude) sandbox profile must include `$XDG_RUNTIME_DIR` in its writable roots. Ask the operator to rerun `~/Coding/0_agents/install-codex-config.sh` (or the Claude equivalent) and start a fresh agent session.
- **No viewer found** — `markdown-view` falls back to `less -R` automatically. If even `less` is missing, error out cleanly; don't paste the file inline.

## Notes

- The script is at `~/.local/bin/markdown-view`, installed by `install-bin.sh`.
- A backward-compat symlink `~/.local/bin/plan-view → markdown-view` is also installed (so existing shell aliases and habits keep working).
- Don't use GUI open commands (`xdg-open`, `open`) over SSH unless explicitly requested.
- Don't modify the file just to open it — `markdown-view` is read-only.

## Backward compatibility

This skill replaces the older `plan-view` skill. The old skill's behavior is preserved — same CLI interface, same fallback chain, same Zellij pane layout. The only change is the name (markdown-view is broader: it's not just for plans).
