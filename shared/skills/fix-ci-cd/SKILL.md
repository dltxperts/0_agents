---
name: fix-ci-cd
description: Triage and repair a RED CI run on an open PR. Forensic counterpart to ship-pr — given GitHub Actions failures, find the true root cause (which may live on the base branch, not your PR), reproduce it locally with a warm cache, fix one failure at a time, and verify with the SAME command CI runs before every push. Use when a PR's CI is failing and you need to get it green without burning CI minutes on blind pushes.
user-invocable: true
disable-model-invocation: false
---

# fix-ci-cd — get a red PR back to green without guessing

## The cardinal rule

**Никогда не быть самонадеянным. ВСЕ ВСЕГДА ПРОВЕРЯТЬ ЛОКАЛЬНО ПЕРЕД PUSH.**

Every PR push triggers the full GitHub Actions matrix (~15 min, real money).
A blind push "to see if it's green now" is a bug in your process. You earn a
push only after the EXACT command CI failed on passes locally on the SAME
tree CI will build.

Two corollaries that cost real time on PR #27 (the session this skill is
distilled from):

1. **`cargo check` / `cargo clippy` ≠ `cargo test`.** Compilation passing
   proves the code *builds*, not that it *behaves*. A missing SQL column,
   a logic regression, a stale test premise — all compile clean and only
   blow up under `cargo test`. If CI's red job ran `cargo test`, you must
   run `cargo test` locally, not `cargo check`.

2. **CI builds the MERGE ref, not your branch.** For a `pull_request`
   event, Actions checks out `refs/pull/<N>/merge` = `base_branch ∪ PR_head`.
   If the base branch (`staging` / `main`) is itself broken, your green
   branch still goes red in CI. Fixing only your PR is necessary but may
   not be sufficient — see Stage 2.

## When to use

- An open PR has one or more failing required checks.
- "All PRs are stuck" — a shared base branch broke and every PR inherits it.
- A check that was green yesterday went red after a base-branch merge.

Do NOT use for:
- Opening a fresh PR — that's `ship-pr` (prevent red, don't repair it).
- Local-only compile errors with no PR yet — just fix and run the suite.

## Protocol

### Stage 0 — read the actual failure (never assume)

The reported cause is a hypothesis, not a diagnosis. On PR #27 the human
said "mold linker broke CI"; the real failure set was five distinct things
stacked (missing linker on runner, rustfmt drift, three flavours of test
API drift, a real SQL bug, a stale test premise). Read the logs first.

```bash
# 1. Identify the latest run for the PR's branch.
gh run list --repo <owner>/<repo> --branch <pr-branch> --limit 3 \
  --json databaseId,status,conclusion,headSha

# 2. Per-job conclusions (which jobs are red).
gh api repos/<owner>/<repo>/actions/runs/<run-id>/jobs \
  --jq '.jobs[] | "\(.conclusion // "running")\t\(.name)"'

# 3. The failing job's log. `gh run view --log-failed` works when the token
#    has scope; if it 403s on annotations, hit the API directly:
gh api repos/<owner>/<repo>/actions/jobs/<job-id>/logs 2>&1 \
  | grep -E 'error\[|^error:|panicked|FAILED|Diff in|invalid linker|^thread' \
  | head -40
```

Grep patterns worth memorising — each maps to a failure class:
| pattern in log                              | class                         |
|---------------------------------------------|-------------------------------|
| `Diff in .../file.rs:NN`                    | `cargo fmt --check` drift     |
| `error[E0061]` / `error[E0063]`             | API signature / struct drift  |
| `invalid linker name in argument`           | missing linker on runner      |
| `panicked at ...` + `assertion ... failed`  | runtime test logic / data bug |
| `warning: ... -D warnings`                  | clippy lint promoted to error |

### Stage 1 — locate the truth: your PR vs the base branch

Find out whether the failing files are even touched by your PR. This is the
single highest-leverage step — it tells you whether to fix the PR or the base.

```bash
git fetch origin <base-branch>          # base = the PR's target (main/staging)
BASE=origin/<base-branch>

# What does the PR actually change?
git diff --name-only "$BASE...HEAD" | sort -u

# Is the failing file in that set?
#  - YES  → your change broke it. Fix on this branch.
#  - NO   → it is broken on the base branch already; CI exposes it through
#           the merge ref. Confirm by checking the base directly:
git show "$BASE:path/to/failing_file.rs" | sed -n '...'
```

If the failure is pre-existing on the base, you have two honest options —
**name them to the user, don't pick silently**:
- **(a)** bundle the base-branch fix into this PR (fastest unblock; once the
  PR merges, the base is clean and every other stuck PR goes green on its
  next run);
- **(b)** open a separate small fix-PR straight to the base branch.

### Stage 2 — reproduce the MERGE ref locally

CI builds `base ∪ PR_head`. To run the exact tree locally, bring your branch
up to the current base. Per the project git rule, **rebase** (the hook bans
`git merge origin/<base>` from inside a worktree):

```bash
git fetch origin <base-branch>
git rebase origin/<base-branch>
```

After rebase your worktree now contains the same files CI compiles —
including files your PR never touched but which the merge pulls in. This is
why a failure "you didn't write" suddenly reproduces locally. Good.

> Gotcha seen on PR #27: a `git revert` commit can get *skipped* by rebase
> ("skipped previously applied commit") when the base already contains an
> equivalent change. Re-check the working tree after rebase — if a config
> block you expected (e.g. the `[profile.release]` / linker section) is
> gone, re-apply it with a fresh `git revert <sha>` or a direct edit.

### Stage 3 — fix ONE failure class, verify with CI's exact command

Warm the cache by pointing at the main checkout's `target/` so each local
run is ~1 min instead of a cold ~10 min:

```bash
export CARGO_TARGET_DIR=<main-repo-root>/target
```

Then run the **same command the red job ran** (read it from the log, not
from memory). Map per class:

```bash
# compile gate (fmt + clippy)
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings

# a single failing integration test (fast iteration) — note the `--`:
MAGNIS_PGLITE_SERVER_BIN=$(scripts/codex/build-pglite-sidecar.sh | tail -1) \
RUST_TEST_THREADS=4 MAGNIS_TEST_PG_POOL=4 \
  cargo test --workspace --test integrations -- <test_name_1> <test_name_2>

# then the WHOLE affected suite(s) before declaring the class fixed:
cargo test --workspace --test integrations -- stage_01_runtime_kernel stage_05_full_process_runtime
```

`cargo test` filter syntax bites: positional filters go **after `--`**, and
each is an independent OR substring match. `cargo test A B` (no `--`) errors
with "unexpected argument B".

Fix categories actually seen, with the canonical fix:
- **Missing linker on runner** — either move the host-only tuning out of the
  repo `.cargo/config.toml` into the dev box's `~/.cargo/config.toml`, OR
  install the tool on the runner (`apt-get install -y mold`) in every Linux
  cargo job. Keep the dev fast-build; don't break CI.
- **rustfmt drift** — `cargo fmt --all`, commit as a `style:` change.
- **API signature drift in tests** (a param/field was added on the base) —
  update the call sites to the new shape (`&[]` empty slice, `None`, etc.);
  match the pattern already used by sibling tests in the same dir.
- **Real product bug** (e.g. an `INSERT` missing a column another impl
  already has) — fix the source, not the test. Confirm by reading the
  sibling impl that does it right.
- **Stale test premise** (test asserts X is "not a tool" but X was promoted
  to a tool since) — fix the test to a still-valid example; leave a comment
  naming the commit that changed the premise so the next person isn't
  confused.

### Stage 4 — push only when locally green, then watch

```bash
# Fast-forward if the remote tip is your previous push; otherwise (after a
# rebase) use the lease — NEVER bare --force.
git push origin <local-branch>:<pr-branch>
# or, post-rebase:
git push --force-with-lease=<pr-branch>:<last-known-remote-sha> \
  origin <local-branch>:<pr-branch>
```

Then watch the run for the SHA you just pushed to completion:

```bash
RUN=$(gh run list --repo <owner>/<repo> --branch <pr-branch> --limit 1 \
        --json databaseId --jq '.[0].databaseId')
until [ "$(gh api repos/<owner>/<repo>/actions/runs/$RUN --jq .status)" = completed ]; do
  sleep 30
done
gh api repos/<owner>/<repo>/actions/runs/$RUN --jq .conclusion
```

If a NEW failure class appears, loop back to Stage 0 for it. One class per
push — don't speculatively batch-fix things you haven't reproduced.

### Stage 5 — done

PR is green only when **every** required check reports `success` for the
latest SHA (E2E + platform builds included — they're gated behind the
backend/test jobs and only run once those pass). Report the final SHA and a
one-line summary per failure class fixed. Do NOT merge — that's the user's
call (project rule: never push/merge to main or staging unprompted).

## Cost discipline (the rule the user cares most about)

Each red push ≈ 15 CI minutes billed. The whole point of this skill is to
make the local↔CI loop cheap and honest:
- warm `CARGO_TARGET_DIR` so local `cargo test` is ~1 min;
- run the exact failing test first, the full suite second, push third;
- never "push to see"; never report "should be green" before the CI receipt.

## Anti-patterns this skill exists to kill

- "The human said it's X" → fixing X, ignoring the four other stacked causes.
- `cargo check` passes → push → CI runs `cargo test` → red. (check ≠ test.)
- Fixing only the PR branch when the base branch is the broken thing.
- Trusting that local branch == CI tree (it's the *merge* tree — rebase).
- Bare `git push --force` clobbering a concurrent push (use `--force-with-lease`).
- Declaring victory on a green run that isn't the latest SHA.
