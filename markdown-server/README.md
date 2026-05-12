# mdurl — markdown publishing server

A small markdown rendering server for u3775. Lets any user on the box publish a
`.md` file and get back a Tailscale URL with rendered mermaid diagrams and a
dark GitHub-style theme.

## What's in this directory

| File | Purpose |
|------|---------|
| `server.py` | Python HTTP server (renders markdown, injects mermaid + dark CSS) |
| `mdurl` | Bash CLI for end users (`mdurl <file.md>` → URL) |
| `markdown-server.service` | systemd unit (runs `server.py` as the `mdview` user) |
| `install.sh` | Root installer (creates `mdview`, drops binaries, enables service) |
| `install-skill.sh` | Per-user fallback installer for Claude/Codex skill symlinks |
| `SKILL.md` | Symlink to the shared `mdurl` skill |

## Install

mdurl uses a two-stage install. System-level install is a separate one-shot
script (`setup-mdurl.sh`); the shared Claude/Codex skill is wired into the
regular `update.sh` so every user picks it up on their next update.

### 1. Server-side (once per host, as root)

```bash
sudo bash ~/Coding/0_agents/setup-mdurl.sh
```

`setup-mdurl.sh` is **independent** of `setup-server.sh` -- the regular
server bootstrap does not install mdurl. This is intentional: mdurl is opt-in
because it opens a network port and creates a system user.

What it does (delegating to `markdown-server/install.sh`):

1. Creates the `mdview` system user (no shell, no home-dir login).
2. Installs `python3-markdown` if missing.
3. Creates `/srv/markdown/` (mode `1777`, sticky like `/tmp`) so any user can
   publish without group plumbing, but only the owner can delete their own.
4. Installs `server.py` → `/usr/local/bin/markdown-server` and `mdurl` →
   `/usr/local/bin/mdurl`.
5. Drops the systemd unit at `/etc/systemd/system/markdown-server.service`,
   `daemon-reload`, `enable --now`.
6. Smoke-tests `http://127.0.0.1:6420/`.

To uninstall:

```bash
sudo bash ~/Coding/0_agents/setup-mdurl.sh uninstall
```

### 2. Per-user skills (each user, via the regular update flow)

```bash
bash ~/Coding/0_agents/update.sh
```

`update.sh` runs as the regular user (no sudo). The canonical skill lives at
`shared/skills/mdurl`; repo symlinks expose it as `claude/skills/mdurl` and
`codex/skills/mdurl`, and `install.sh` publishes those into `~/.claude` and
`~/.codex`.

To run only the fallback skill installer (skipping everything else):

```bash
bash ~/Coding/0_agents/markdown-server/install-skill.sh
```

### Stand-alone scripts (escape hatch)

| Script | Who invokes |
|--------|-------------|
| `markdown-server/install.sh` | called by `setup-mdurl.sh` |
| `markdown-server/install-skill.sh` | manual fallback for per-user skill symlinks |

You typically don't run these directly.

## Usage

```bash
# publish (or refresh) a file
mdurl ~/Coding/securitize/research.md
# -> http://u3775:6420/gearbox/research

# custom slug
mdurl ~/quarterly.md q1-2026
# -> http://u3775:6420/gearbox/q1-2026

# list YOUR docs
mdurl -l

# list everyone's docs
mdurl -L

# remove one of YOUR docs
mdurl -r research
```

Files are **copied**, not symlinked, into `/srv/markdown/<user>/<slug>.md`.
This is intentional: home directories are mode `750` on this host, so the
`mdview` service user cannot follow symlinks into them. Re-run `mdurl` after
editing the source to refresh.

## URL pattern

```
http://u3775:6420/                    # index of every published doc
http://u3775:6420/<user>/<slug>       # rendered doc
```

Authentication: none on the HTTP layer. Reachability is gated by Tailscale —
only nodes in your tailnet can reach `u3775:6420`. Don't publish secrets.

## Architecture

```
+---------------------------+      +--------------------------------+
| /srv/markdown/<user>/*.md |<-----| mdurl CLI (run by any user)    |
| (1777 sticky world-write) |      | copies file in, prints URL     |
+--------------+------------+      +--------------------------------+
               |
               v read-only
+---------------------------+      +--------------------------------+
| markdown-server.service   |----->| python3-markdown + mermaid.js  |
| User=mdview, port 6420    |      | dark theme + responsive layout |
| ProtectHome=true          |      +--------------------------------+
+---------------------------+
```

The `mdview` user has no shell, no home-dir login, `ProtectHome=true` in the
unit. Compromise of the renderer process does not grant access to anyone's
home directory.

## Operations cheatsheet

```bash
systemctl status markdown-server          # health
systemctl restart markdown-server         # reload after server.py change
journalctl -u markdown-server -f          # live logs
sudo bash install.sh uninstall            # tear down (keeps /srv/markdown)
```

## Why a separate user instead of running under `gearbox`

The renderer parses untrusted markdown. A bug (or future markdown extension
with parser quirks) shouldn't grant the process access to your home directory,
SSH keys, or git credentials. `User=mdview` + `ProtectHome=true` enforces that.
