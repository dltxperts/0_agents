#!/usr/bin/env bash
# Bootstrap a Linux server as an agent host (Claude Code + Codex + tooling).
#
# Idempotent — re-runs detect what's already in place and only update what's
# missing. Safe to use as the standard "bring this server up to current
# baseline" command after every git pull.
#
# What this installs (in order):
#   0. Sanity checks (running as user, basic tools present)
#   1. Node (via nvm)
#   2. Bun
#   3. cloudflared (system tool — Cyrus, dev tunnels, anything else)
#   4. install.sh --server  (claude+codex symlinks + wide-permission settings)
#   5. install-bin.sh       (~/.local/bin/markdown-view, frogmouth-tuned, ...)
#   6. install-codex.sh     (Codex config.toml render)
#   7. install-runtimes.sh  (claude-code + codex npm CLIs)
#   8. install-linear-mcp.sh (Linear MCP register; OAuth login deferred)
#   9. install-lazyvim.sh   (LazyVim — useful on Ubuntu where apt nvim is old)
#  10. Subscription logins (interactive: claude /login, codex login)
#  11. Zellij session label
#
# Does NOT do:
#   - Cyrus bootstrap (use setup-cyrus.sh AFTER this)
#   - Mac-specific things (use setup-mac.sh)
#   - User creation (do that as root: 'sudo adduser X; sudo loginctl enable-linger X')
#   - SSH keys (do that yourself: 'ssh-keygen -t ed25519')
#   - Repo clone (you've already cloned to run this script)
#
# Run AS THE TARGET USER, not root.
#
# Optional environment overrides:
#   NODE_VERSION    default: 20
#   NVM_VERSION     default: v0.40.1
#
# Usage:
#   setup-server.sh                 # full bootstrap
#   setup-server.sh --no-runtimes   # skip claude/codex npm install (faster reruns)
#   setup-server.sh --no-lazyvim    # skip LazyVim install
#   setup-server.sh --no-logins     # skip interactive subscription logins

set -euo pipefail

DO_RUNTIMES=1
DO_LAZYVIM=1
DO_LOGINS=1
for arg in "$@"; do
  case "$arg" in
    --no-runtimes) DO_RUNTIMES=0 ;;
    --no-lazyvim)  DO_LAZYVIM=0 ;;
    --no-logins)   DO_LOGINS=0 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NODE_VERSION="${NODE_VERSION:-20}"
NVM_VERSION="${NVM_VERSION:-v0.40.1}"

say()   { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
warn()  { printf "\n\033[1;33m⚠ %s\033[0m\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
err()   { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ─── 0. Sanity ──────────────────────────────────────────────────────────────
say "Sanity checks"
[[ "$(id -u)" -ne 0 ]] || err "Do NOT run as root. Switch to your agent user (e.g. 'sudo -iu vibe') and rerun."
for c in bash curl git ssh; do
  command -v "$c" >/dev/null || err "$c is missing. Install via your package manager and rerun."
done
ok "running as $(whoami) on $(uname -s) $(uname -m)"

[[ "$(uname -s)" == "Linux" ]] || warn "This script is targeted at Linux. macOS has its own setup-mac.sh."

# ─── 1. Node via nvm ────────────────────────────────────────────────────────
say "Node $NODE_VERSION (via nvm)"
if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  ok "nvm $NVM_VERSION installed"
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
if ! command -v node >/dev/null \
     || [[ "$(node -v 2>/dev/null | sed 's/^v//;s/\..*//')" -lt "$NODE_VERSION" ]]; then
  nvm install "$NODE_VERSION"
  nvm alias default "$NODE_VERSION"
fi
nvm use default >/dev/null
ok "node $(node --version), npm $(npm --version)"

# ─── 2. Bun ─────────────────────────────────────────────────────────────────
say "Bun"
if [[ ! -x "$HOME/.bun/bin/bun" ]]; then
  curl -fsSL https://bun.sh/install | bash
fi
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
ok "bun $(bun --version)"

# ─── 3. cloudflared ─────────────────────────────────────────────────────────
say "cloudflared"
if ! command -v cloudflared >/dev/null; then
  case "$(uname -m)" in
    x86_64)        CFD_ARCH=amd64 ;;
    aarch64|arm64) CFD_ARCH=arm64 ;;
    *) err "Unsupported arch $(uname -m) — install cloudflared manually and rerun." ;;
  esac
  mkdir -p "$HOME/.local/bin"
  curl -L --fail \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CFD_ARCH}" \
    -o "$HOME/.local/bin/cloudflared"
  chmod +x "$HOME/.local/bin/cloudflared"
fi
export PATH="$HOME/.local/bin:$PATH"
ok "cloudflared $(cloudflared --version 2>&1 | head -1)"

# ─── 4. Repo-managed agent config (server mode) ─────────────────────────────
if [[ -x "$REPO_DIR/install.sh" ]]; then
  say "Installing agent config from $REPO_DIR (server mode)"
  bash "$REPO_DIR/install.sh" --server
else
  err "install.sh not found alongside this script — abort"
fi

# ─── 5. ~/.local/bin helpers (markdown-view, frogmouth-tuned, ...) ──────────
if [[ -x "$REPO_DIR/install-bin.sh" ]]; then
  say "Installing ~/.local/bin helpers"
  bash "$REPO_DIR/install-bin.sh"
fi

# ─── 6. Codex config.toml render ────────────────────────────────────────────
if [[ -x "$REPO_DIR/install-codex.sh" ]]; then
  say "Rendering Codex config.toml"
  bash "$REPO_DIR/install-codex.sh"
fi

# ─── 7. Runtimes (claude-code + codex npm CLIs) ─────────────────────────────
if [[ "$DO_RUNTIMES" -eq 1 && -x "$REPO_DIR/install-runtimes.sh" ]]; then
  say "Installing agent runtimes"
  bash "$REPO_DIR/install-runtimes.sh"
else
  warn "skipping runtimes install (--no-runtimes or install-runtimes.sh missing)"
fi

# ─── 8. Linear MCP register ─────────────────────────────────────────────────
if [[ -x "$REPO_DIR/install-linear-mcp.sh" ]]; then
  say "Registering Linear MCP"
  # OAuth login is interactive and requires a browser — print instructions
  # but don't block the bootstrap; user can finish login on their laptop.
  bash "$REPO_DIR/install-linear-mcp.sh" || warn "install-linear-mcp.sh exited non-zero (continuing)"
fi

# ─── 9. LazyVim ─────────────────────────────────────────────────────────────
if [[ "$DO_LAZYVIM" -eq 1 && -x "$REPO_DIR/install-lazyvim.sh" ]]; then
  say "Installing LazyVim"
  bash "$REPO_DIR/install-lazyvim.sh"
else
  warn "skipping LazyVim install (--no-lazyvim or install-lazyvim.sh missing)"
fi

# ─── 10. Subscription logins (interactive) ──────────────────────────────────
if [[ "$DO_LOGINS" -eq 0 ]]; then
  warn "skipping subscription logins (--no-logins). Run manually:"
  echo "    claude         # then /login"
  echo "    codex login"
else
  say "Claude Code subscription login"
  if [[ -f "$HOME/.claude/.credentials.json" ]]; then
    ok "claude-code already authenticated ($HOME/.claude/.credentials.json present)"
  else
    echo "  Running 'claude setup-token' — open the printed URL, sign in, paste back."
    claude setup-token \
      || warn "setup-token failed; finish manually: run 'claude' then '/login'"
  fi

  say "Codex subscription login"
  if [[ -f "$HOME/.codex/auth.json" ]]; then
    ok "codex already authenticated ($HOME/.codex/auth.json present)"
  else
    codex login \
      || warn "codex login exited non-zero — retry with 'codex login'"
  fi
fi

# ─── 11. Zellij session label ──────────────────────────────────────────────
if command -v agent-session-name >/dev/null 2>&1; then
  say "Naming terminal session"
  agent-session-name "${AGENT_SESSION_NAME:-$(whoami)}" || true
fi

# ─── Summary ────────────────────────────────────────────────────────────────
say "Done."
cat <<EOF
  Repo            : $REPO_DIR @ $(cd "$REPO_DIR" && git rev-parse --short HEAD)
  Node            : $(node --version)
  Bun             : $(bun --version)
  cloudflared     : $(cloudflared --version 2>&1 | head -1 | awk '{print $3}')
  claude-code     : $(claude --version 2>/dev/null | head -1)
  codex           : $(codex --version 2>/dev/null | head -1)

  Symlinks installed:
    ~/.claude/{CLAUDE.md, agents, skills, lang}
    ~/.claude/settings.json     (server-side wide-permission profile)
    ~/.codex/{skills/*, agents, lang}
    ~/.codex/config.toml        (server-side workspace-write profile)
    ~/.local/bin/{markdown-view, frogmouth-tuned, agent-session-name, plan-view}

  Next steps:
    - If this host is meant to run Cyrus: bash $REPO_DIR/setup-cyrus.sh
    - To re-apply latest 0_agents changes anytime: bash $REPO_DIR/update.sh
    - To edit code from terminal: nvim (LazyVim is configured)
EOF
