---
name: launch-e2e
description: "Launch a project E2E stack on free ports using the repository launcher script. Finds free ports, starts services, verifies health, and optionally runs Playwright."
user-invocable: true
disable-model-invocation: false
---

# Launch E2E Stack

Launch an isolated E2E environment for testing. Use the repo launcher script
when one exists so startup is one stable command and the process tree survives
tool timeouts.

## Usage

```bash
/launch-e2e                              # just start the stack
/launch-e2e <spec>                       # start stack + run spec
/launch-e2e --headed <spec>              # headed Playwright run
/launch-e2e --keep <spec>                # keep stack alive after the spec
```

## Protocol

### Step 1: Detect Environment

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
SESSION_NAME="launch-e2e-$(basename "$REPO_ROOT")"
STATUS_FILE="/tmp/${SESSION_NAME}.status"
```

### Step 2: Launch Via Repo Script In tmux

`tmux` is the stable launch surface here: one command starts the stack inside
a persistent session. The actual orchestration must live in a repo-provided
launcher script, preferably `scripts/launch-e2e.sh`.

```bash
tmux has-session -t "$SESSION_NAME" 2>/dev/null && tmux kill-session -t "$SESSION_NAME" || true
rm -f "$STATUS_FILE"
test -x scripts/launch-e2e.sh || { echo "Missing scripts/launch-e2e.sh"; exit 1; }
tmux new-session -d -s "$SESSION_NAME" \
  "cd '$REPO_ROOT' && scripts/launch-e2e.sh $ARGUMENTS | tee '$STATUS_FILE'"
```

### Step 3: Read Status

Wait for the status file to appear. The launcher output is the source of truth for chosen ports, DB name, and log paths.

```bash
for i in $(seq 1 90); do
  [ -f "$STATUS_FILE" ] && break
  sleep 2
done
cat "$STATUS_FILE"
```

### Step 4: Test Execution

If the user passed a spec, the repo script already ran it with the correct `BASE_URL` / `WS_URL`. Do not rerun Playwright manually unless debugging a failed launch.

### Step 5: Cleanup (unless `--keep`)

```bash
tmux kill-session -t "$SESSION_NAME"
```

## Output

```
E2E stack launched:
  Backend:  http://localhost:<port>
  Agent:    http://localhost:<port> [engine: scripted-available|builtin]
  Frontend: http://localhost:<port>
  Database: <isolated test database, if applicable>
Test: <PASSED|FAILED|not requested>
Logs:
  Backend:  /tmp/e2e-backend-<port>.log
  Agent:    /tmp/e2e-agent-<port>.log
  Frontend: /tmp/e2e-frontend-<port>.log
```

## Task

$ARGUMENTS
