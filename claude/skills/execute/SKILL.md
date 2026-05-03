---
name: execute
description: Route an approved plan to execution — local (this session switches into executor mode) or remote (Linear issue for Cyrus). Asks "где?" if not specified in args. Use when planning is done and the user says "execute" / "запусти" / "погнали" / "ship it".
user-invocable: true
disable-model-invocation: true
---

# Execute

Route an approved plan to its execution surface. Two destinations:

- **local** — this conversation switches to executor mode and runs the plan
- **remote** — create a Linear issue with the plan, assign to the Cyrus bot;
  Cyrus spawns a remote Claude session that picks it up

The same executor rules apply in both modes.

## Prerequisites

- An approved plan exists in this conversation (from /spec or /plan).
- For remote: Linear MCP is connected, the Cyrus bot user is known.

## Executor rules (shared by both routes)

The following block is the contract — embedded verbatim into the Linear
issue (remote route) or applied to this conversation (local route):

```
You are an executor for an already-finalized plan. Do NOT invoke /spec,
/plan, /quick-fix, /dictate, or any other planning / interactive skill.
Do NOT re-plan, re-scope, or "improve" the plan. If something is
ambiguous, ASK the user (or comment in the Linear issue thread) — never
silently change scope.

Execute the plan stage by stage per CLAUDE.md "Always-on principles"
(TDD, commit discipline via /git, no fallbacks, explore-before-edit).
Use /verify-app, /verify-frontend, /bug, /git, /completion-note as
helpers between stages.

Stage transitions are AUTOMATIC. Do NOT pause between stages to ask
"continue or review?" / "запустить дальше или подождать?" — move from
stage N to stage N+1 immediately after the previous stage's commit.
Stop ONLY on: (1) stage failure (tests fail, hook blocks, build breaks),
(2) plan ambiguity that the plan text doesn't resolve, (3) explicit user
interrupt. Each commit is a natural pause point — the user can interrupt
there if they want to step in.

Default exit: open a PR (do not merge to main/staging), end with
/completion-note.

Optional for long executions: save these rules to memory before starting
so they survive context compaction.
```

## Protocol

1. Confirm an approved plan exists. If none — abort: "No approved plan
   found. Run /spec or /plan first, then re-run /execute."
2. Determine target from $ARGUMENTS:
   - contains "local" / "локально" / "тут" → **local route**
   - contains "remote" / "ship" / "linear" / "удалённо" → **remote route**
   - empty or ambiguous → ASK the user:
     "Где запускаем?
       - **local** — выполнить тут, в этой сессии
       - **remote** — Linear issue для Cyrus на сервере"
3. Branch:

### Local route

1. Print: "Switching to implementation mode. Planning skills are off the
   table for the rest of this session. Executing the plan now."
2. Apply the Executor rules above to the rest of this conversation.
3. Begin executing stage 1.

### Remote route

1. Confirm with the user: target Linear team / project, bot user (e.g.
   "cyrus-vibe"), and issue title.
2. Compose the Linear issue body:

       # Implementation mode

       <Executor rules block from above, verbatim>

       ## Plan

       <verbatim plan content>

3. Create the Linear issue via Linear MCP, assigned to the Cyrus bot.
4. Return: issue URL + one-line confirmation, e.g.
   "Shipped to <bot>. Cyrus picks up via webhook; logs:
   `journalctl --user -u cyrus.service -f`."

## Boundaries

- Do NOT modify the plan content during routing. Verbatim pass-through.
- For remote: do NOT assign to anyone other than the configured Cyrus bot.
  If multiple Linear teams/projects — confirm before creating.
- For local: do NOT skip /completion-note at the end.

## Task

$ARGUMENTS
