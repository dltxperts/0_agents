---
name: verify-frontend
description: Visual verification for frontend changes. Runs the project-configured screenshot tool, saves artifacts to a repo-local path that orchestrators (Cyrus, CI) can pick up and attach to issues / PRs. Auto-invokes on frontend file changes.
user-invocable: true
disable-model-invocation: false
---

# Verify Frontend

Visual changes need visual verification. Typecheck / lint / build are
supporting checks only — they do NOT prove the UI looks or behaves
correctly.

This skill complements `/verify-app` (which runs the deterministic suite)
by producing visual artifacts.

## Setup expected

Project provides command convention via `.claude/temp/env.sh`:

```bash
SCREENSHOT_CMD="..."        # required for this skill to actually run
SCREENSHOT_OUT_DIR="..."    # default: .claude/artifacts/screenshots/$TASK_SLUG/
```

`SCREENSHOT_CMD` is whatever the project uses (Playwright, Puppeteer,
Storybook test-runner, custom script). Contract:

- It MUST honor `OUT_DIR` env var as the destination for image files.
- It MUST exit 0 on success, non-zero on failure.
- It SHOULD NOT depend on long-running services it didn't start; if E2E
  needs a backend, the script handles its own setup/teardown.

If `SCREENSHOT_CMD` is not set, the skill reports SKIPPED and asks the
human to verify visually.

## Protocol

```bash
[ -f .claude/temp/env.sh ] && source .claude/temp/env.sh

TASK_SLUG="${TASK_SLUG:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${SCREENSHOT_OUT_DIR:-.claude/artifacts/screenshots/$TASK_SLUG}"
mkdir -p "$OUT_DIR"

if [ -z "$SCREENSHOT_CMD" ]; then
  echo "SCREENSHOT_CMD not configured — skipping. Add to .claude/temp/env.sh."
  echo "VERIFY_FRONTEND_RESULT: SKIPPED"
  exit 0
fi

OUT_DIR="$OUT_DIR" eval "$SCREENSHOT_CMD"
RC=$?

if [ $RC -eq 0 ]; then
  echo "VERIFY_FRONTEND_RESULT: PASS"
  echo "Artifacts saved to: $OUT_DIR"
  ls -la "$OUT_DIR"
else
  echo "VERIFY_FRONTEND_RESULT: FAIL ($RC)"
  exit $RC
fi
```

## Output format

```text
VERIFY_FRONTEND
---------------
Tool:        $SCREENSHOT_CMD
Output dir:  <path>
Result:      [PASS|FAIL|SKIPPED]
Artifacts:
  - screenshot1.png (Nkb)
  - screenshot2.png (Nkb)
---------------
```

Reference the output path in completion-note as visual proof.

## Integration with orchestrators

Save artifacts under `<repo>/.claude/artifacts/screenshots/<task-slug>/`.
Orchestrators that follow the convention:

- **Cyrus (Linear bot)** — reads this directory after the session and
  attaches the files to the Linear issue / PR comment.
- **Local human review** — referenced path in completion-note; reviewer
  opens locally.
- **CI** — uploads as workflow artifact.

The skill itself does not upload anywhere. It produces artifacts in a
known location and stops.

## Rules

- Do not skip on the basis that "code looks right". Visual changes require
  visual proof.
- Do not delete or overwrite existing artifacts in the output directory.
  Each invocation writes a new task-slugged subdirectory.
- Do not commit `.claude/artifacts/` to git — it should be in `.gitignore`.
