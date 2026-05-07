# 0_agents — Onboarding & Operations

Single source of truth for setting up an agent host (Mac client or Linux server) and keeping it current. Replaces the per-script README skim — read this top-to-bottom once, then come back as needed.

## TL;DR

| Scenario | Command |
|---|---|
| **Fresh Mac client** | `bash ~/Coding/0_agents/setup-mac.sh` |
| **Bare Linux server** (no Cyrus) | `bash ~/Coding/0_agents/setup-server.sh` |
| **Linux server hosting Cyrus** | `bash setup-server.sh && bash setup-cyrus.sh` |
| **Create new agent user** (as root) | `sudo bash ~/Coding/0_agents/create-agent-user.sh <username>` |
| **Existing host — just sync latest** | `bash ~/Coding/0_agents/update.sh` |

All scripts are **idempotent**: re-runs detect what's already in place and only update what's missing or out of date. Running `update.sh` weekly is the maintenance cadence.

---

## What 0_agents provides

A repo of opinionated configs and helpers for two coding agents — **Claude Code** and **Codex** — plus the supporting tooling we use daily:

```
0_agents/
├── claude/                         # Claude Code config (CLAUDE.md, agents, skills)
│   └── skills/                     # User-invocable slash commands (/spec, /plan, ...)
├── codex/                          # Codex config (skills, rules, agents, config.toml)
├── shared/                         # Skills + lang docs reachable from BOTH tools
│   └── skills/                     # bug, completion-note, dictate, fast-precommit,
│                                   # markdown-view, quick-fix, start-work, test-protocol
├── server/                         # Server-only profiles (wide-permission settings)
│   ├── claude/settings.json        # SOURCE OF TRUTH for server-side Claude permissions
│   └── codex/config.toml           # Codex workspace-write profile
├── bin/                            # Helper CLIs installed into ~/.local/bin
│   ├── markdown-view               # Open .md in Zellij pane (frogmouth → glow → less)
│   ├── frogmouth-tuned             # Frogmouth wrapper with sane theming
│   └── agent-session-name          # Set Zellij session label
├── install*.sh                     # Component installers (idempotent)
├── setup-{mac,server,cyrus}.sh     # Bootstrap orchestrators per host type
├── update.sh                       # Re-run all installers after `git pull`
├── macos_hotkey.sh                 # Hammerspoon Cmd-Shift-3 → upload to u3775
└── screenshot-upload.sh            # Used by the hotkey above
```

---

## Pre-requisites you bring yourself

These are intentionally NOT automated — you do them once per machine, then 0_agents takes over.

| Need | Mac | Linux |
|---|---|---|
| `bash`, `curl`, `git`, `ssh` | ✅ ships with macOS | most distros — `apt install -y` if missing |
| Homebrew | https://brew.sh | n/a |
| GitHub SSH key | `ssh-keygen -t ed25519` → paste pubkey at https://github.com/settings/keys |
| Linear OAuth (browser) | one-time per machine in `claude` and `codex` CLIs |

For a server you're going to run **as a different user** (e.g. `vibe`, `marketing`):

```bash
sudo adduser vibe
sudo loginctl enable-linger vibe        # systemd --user persists at logout
sudo -iu vibe                           # become the user, then proceed
```

### Setting up multiple agent users for parallel work

When you need multiple independent agent users working in parallel (e.g., for different projects or workstreams), use the helper script (recommended) or create users manually.

**Option A: Using the helper script (recommended):**

```bash
# As root, run the script for each user
cd ~/Coding/0_agents
sudo bash create-agent-user.sh <username1>
sudo bash create-agent-user.sh <username2>
```

The script creates the user, enables systemd linger, and prints next steps.

**Option B: Manual creation:**

```bash
# As root, create each user
sudo adduser <username1>
sudo adduser <username2>

# Enable systemd --user services to persist after logout
sudo loginctl enable-linger <username1>
sudo loginctl enable-linger <username2>

# Optional: Add to sudo group if needed (only if the user needs elevated privileges)
# sudo usermod -aG sudo <username1>
# sudo usermod -aG sudo <username2>
```

Then, for **each user**, become that user and run the full setup:

```bash
# Setup for first user
sudo -iu <username1>
ssh-keygen -t ed25519 -C "<username1>@$(hostname)"
# → Add the pubkey to https://github.com/settings/keys
git clone git@github.com:dltxperts/0_agents.git ~/Coding/0_agents
bash ~/Coding/0_agents/setup-server.sh
# Optionally: bash ~/Coding/0_agents/setup-cyrus.sh
exit

# Repeat for other users
sudo -iu <username2>
ssh-keygen -t ed25519 -C "<username2>@$(hostname)"
# → Add the pubkey to https://github.com/settings/keys
git clone git@github.com:dltxperts/0_agents.git ~/Coding/0_agents
bash ~/Coding/0_agents/setup-server.sh
# Optionally: bash ~/Coding/0_agents/setup-cyrus.sh
exit
```

Each user will have:
- Independent `~/.claude/` and `~/.codex/` configurations
- Isolated worktrees (if running Cyrus)
- Separate systemd --user services
- Own Linear OAuth tokens and credentials

This allows multiple agent sessions to run in parallel without conflicts.

---

## Scenarios

### A. Fresh Mac client

```bash
git clone git@github.com:dltxperts/0_agents.git ~/Coding/0_agents
bash ~/Coding/0_agents/setup-mac.sh
```

`setup-mac.sh` runs (in order, every step idempotent):
1. **install.sh** — symlink `claude/` + `codex/` + `shared/` into `~/.claude/` and `~/.codex/`
2. **install-bin.sh** — install `markdown-view`, `frogmouth-tuned`, `agent-session-name` into `~/.local/bin/`
3. **install-codex-config.sh** — render `codex/config.toml.template` → `~/.codex/config.toml`
4. **install-runtimes.sh** — `npm install -g @anthropic-ai/claude-code @openai/codex` (installs Node via brew if missing)
5. **install-linear-mcp.sh** — register Linear MCP for both Codex and Claude
6. **install-lazyvim.sh** — Neovim ≥ 0.11 (via brew) + LazyVim starter at `~/.config/nvim`
7. **macos_hotkey.sh** — Hammerspoon + Cmd-Shift-3 → `screenshot-upload.sh` → u3775
8. **Subscription logins** — `claude setup-token`, `codex login` (interactive)

After it finishes, do these manually:
- `brew install --cask tailscale` then log in to Tailscale
- Grant Hammerspoon **Accessibility** access in System Settings → Privacy & Security → Accessibility (if Cmd-Shift-3 doesn't fire)

`~/.claude/settings.json` is **not** installed on Mac — the Mac uses its own personal settings (the wide-permission profile is server-only, see `server/claude/settings.json`).

### B. Bare Linux server (no Cyrus)

Use this for any agent host where you want Claude + Codex tooling but not the full Cyrus orchestrator (e.g. a personal dev VM).

```bash
git clone git@github.com:dltxperts/0_agents.git ~/Coding/0_agents
bash ~/Coding/0_agents/setup-server.sh
```

`setup-server.sh` does, in order:
1. Sanity (must run as user, not root; bash/curl/git/ssh present)
2. **Node** via nvm
3. **Bun**
4. **cloudflared** (system tool — useful regardless of Cyrus)
5. **install.sh --server** (claude+codex symlinks **+** server-side wide-permission `settings.json`)
6. **install-bin.sh**
7. **install-codex-config.sh**
8. **install-runtimes.sh**
9. **install-linear-mcp.sh**
10. **install-lazyvim.sh** (avoids old Ubuntu apt nvim — fetches GitHub stable tarball into `~/.local/share/nvim-prebuilt/` and symlinks `~/.local/bin/nvim`)
11. Subscription logins (interactive)
12. Zellij session label

### C. Linux server hosting Cyrus

```bash
bash ~/Coding/0_agents/setup-server.sh   # see above
bash ~/Coding/0_agents/setup-cyrus.sh    # adds Cyrus on top
```

`setup-cyrus.sh` is intentionally narrow — it pre-flights that `setup-server.sh` already ran (node, bun, cloudflared, claude, codex must all exist) and STOPS otherwise. Then:
1. Install `cyrus-ai` npm CLI
2. `cloudflared tunnel login` (browser flow — once per Cloudflare zone)
3. Create `~/.cyrus/`
4. Cloudflare tunnel + DNS route + per-tunnel config file
5. Env file (Linear OAuth Application secrets — manual UI step at https://linear.app/settings/api/applications/new)
6. systemd `--user` units (`cyrus.service` + `cloudflared-<bot>.service`)
7. Start tunnel
8. `cyrus self-auth-linear` (browser flow)
9. `cyrus self-add-repo` (interactive — paste git SSH URL)
10. Per-repo runner config hint
11. Start Cyrus
12. Cleanup origin cert (`cert.pem`) — leaves running tunnel intact

After this, assigning a Linear issue to your bot user fires the webhook, and Cyrus spawns an agent session in `~/.cyrus/worktrees/<MAG-N>/`.

### D. Existing host — sync latest

After `git pull` on `0_agents`, or on a maintenance cadence:

```bash
bash ~/Coding/0_agents/update.sh                      # client mode
bash ~/Coding/0_agents/update.sh --server             # server mode (applies wide-permission settings)
```

`update.sh` does:
1. `git pull --ff-only` (aborts on diverged history; resolve manually)
2. `install.sh` (with `--server` passthrough)
3. `install-bin.sh`
4. `install-codex-config.sh`
5. `install-runtimes.sh` (upgrades claude-code + codex npm globals)
6. `install-linear-mcp.sh` (idempotent re-register)
7. `install-lazyvim.sh` (auto-detected if `~/.config/nvim/lua/config/lazy.lua` exists, or via `--with-lazyvim`)

Skip individual steps with `--skip <name>` (`git`, `install`, `bin`, `codex-config`, `runtimes`, `linear-mcp`, `lazyvim`).

---

## Component installer reference

Each component installer can be called directly when you only need a slice.

| Script | Purpose | Idempotent? |
|---|---|---|
| `install.sh` | symlinks `claude/`, `codex/`, `shared/` into `~/.claude/` + `~/.codex/`; registers Codex MCP in Claude. `--server` adds wide-permission `settings.json`. | ✅ |
| `install-bin.sh` | `~/.local/bin/markdown-view` + `frogmouth-tuned` + `agent-session-name` (+ backward-compat `plan-view` symlink) | ✅ |
| `install-codex-config.sh` | render `codex/config.toml.template` → `~/.codex/config.toml` (HOME substitution); `.bak.<ts>` if existing differs | ✅ |
| `install-runtimes.sh` | `npm install -g @anthropic-ai/claude-code @openai/codex`. `--check` reports versions. `--skip-claude` / `--skip-codex` narrow scope. | ✅ (upgrade) |
| `install-linear-mcp.sh` | register Linear MCP for both Codex and Claude. Codex login is interactive on local sessions; SSH prints `ssh -L` instructions. | ✅ |
| `install-lazyvim.sh` | Neovim ≥ 0.11 (or fetches GitHub stable on Linux) + LazyVim starter. `--no-nvim` keeps your nvim. `--force` reinstalls LazyVim. | ✅ |

---

## Skills layout (Claude + Codex)

Skills are user-invocable slash commands like `/spec`, `/plan`, `/dispatch-to-linear`. They live in three places:

- **`shared/skills/<name>/SKILL.md`** — canonical for skills both tools should see. `claude/skills/<name>` and `codex/skills/<name>` are symlinks to here.
- **`claude/skills/<name>/SKILL.md`** — Claude-only. Either Claude-specific behavior, or a copy that intentionally diverges from the Codex twin.
- **`codex/skills/<name>/SKILL.md`** — Codex-only.

When you change a skill, check both directories before assuming you're done. There are 5 deliberately-divergent pairs (`spec`, `plan`, `review-plan`, `review-implementation`, `verify-frontend`) — they share most of the body but reference `CLAUDE.md` vs `AGENTS.md` and use Codex via MCP vs directly. Future cleanup may merge them with parameter substitution; for now, sync manually.

Notable shared skills:
- **`/markdown-view`** — open any `.md` file in a separate Zellij pane (preferred over pasting long markdown into chat)
- **`/start-work`** — implement an approved plan locally with worktree + TDD discipline
- **`/dispatch-to-linear`** + **`/execute-from-linear`** — handoff a plan to Cyrus's bot for autonomous implementation

---

## Verification

After install, run the diagnostics:

```bash
bash ~/Coding/0_agents/doctor.sh           # client-mode checks
bash ~/Coding/0_agents/doctor.sh --server  # also verify server profile + Cyrus
bash ~/Coding/0_agents/doctor.sh --quiet   # only print failures
```

`doctor.sh` is read-only — it never changes anything, just reports what's there. Exit code 0 = all green; 1 = soft fail (something drifted; the failure line tells you which `install-*.sh` to re-run). Useful after `update.sh` and any time something feels off.

Manual spot-checks if `doctor.sh` is unavailable:

```bash
claude --version                  # 2.x
codex --version                   # 0.12.x
markdown-view --help              # prints usage
claude mcp list                   # codex + linear should appear
codex mcp list                    # linear should appear
ls -la ~/.claude/skills           # symlinks into 0_agents
ls -la ~/.codex/skills            # mix of system + 0_agents symlinks

# server only
ls -la ~/.claude/settings.json    # → 0_agents/server/claude/settings.json
systemctl --user status cyrus     # if Cyrus is set up
nvim --version                    # 0.11.x
```

---

## Troubleshooting

### Push refused — `Permission to <repo>.git denied to <user>`
Your fine-grained PAT lacks write access to the repo. Add the repo to the PAT's Repository access list at https://github.com/settings/personal-access-tokens, then `git push` again. (Org-owned repos like `dltxperts/*` need explicit grant even if you own the personal `0xmikko/*` fork the redirect points at.)

### Push refused — workflow scope missing
GitHub blocks PAT pushes that touch `.github/workflows/` without `Workflows: Read and write` permission. Add it to the PAT and retry.

### `ssh-add -l` fails / `Could not open authentication agent`
Either start `ssh-agent` (`eval $(ssh-agent)`) or use `ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes` directly.

### LazyVim fails on Ubuntu — `module 'vim.fs' not found` or similar
The system nvim is too old. Either:
- Run `bash install-lazyvim.sh` (it installs latest into `~/.local/bin/nvim`, sidesteps apt)
- Or `apt remove neovim` and let LazyVim manage it

### Codex OAuth callback hangs over SSH
Codex tries to bind 127.0.0.1:1455 on the server; your local SSH session needs to forward that port:
```bash
ssh -L 1455:localhost:1455 user@server
codex login    # opens URL, callback now reaches your laptop
```

### Cyrus tunnel "DNS route already exists"
Re-running `setup-cyrus.sh` is safe — the script detects the existing CNAME and reuses it. If the assertion fails because the CNAME points somewhere else, fix it manually in Cloudflare and re-run.

---

## Update cadence

- **After every `git pull` on this repo** → `bash update.sh`
- **After CLI publishes a new version** (claude-code or codex) → `bash install-runtimes.sh`
- **After a fresh git clone on a new host** → `setup-mac.sh` or `setup-server.sh`

The repo's own update cadence: small focused commits, one PR per logical change. CI is in `.github/workflows/` (just typecheck for now).

---

## Related repos

- **`dltxperts/content-os`** — content authoring + publishing pipeline; uses 0_agents skills heavily
- **`dltxperts/magnis-app`** — separate product workspace; also pulls 0_agents

Both are configured per-project via their own `.claude/settings.json` (allows narrower than server profile, but **never** overrides the deny block in `0_agents/server/claude/settings.json`).
