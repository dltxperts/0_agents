#!/usr/bin/env bash
# Install or upgrade the agent CLI runtimes: claude-code + codex.
# Idempotent: re-running upgrades only what's outdated.
#
# Both CLIs are distributed as npm globals. This script:
#   1. Verifies node + npm are present and recent enough.
#   2. Installs / upgrades:
#        @anthropic-ai/claude-code   (binary: claude)
#        @openai/codex               (binary: codex)
#   3. Reports installed versions.
#
# This script does NOT log you in to either CLI — that's interactive.
# For that:
#   claude       # then /login (Anthropic OAuth)
#   codex login  # OpenAI OAuth
#
# Usage:
#   install-runtimes.sh                  # install/upgrade both
#   install-runtimes.sh --skip-claude    # only codex
#   install-runtimes.sh --skip-codex     # only claude-code
#   install-runtimes.sh --check          # report versions only, no install

set -euo pipefail

SKIP_CLAUDE=0
SKIP_CODEX=0
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --skip-claude) SKIP_CLAUDE=1 ;;
    --skip-codex)  SKIP_CODEX=1 ;;
    --check)       CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
ok()   { printf '✓ %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# ─── Prereqs ─────────────────────────────────────────────────────────────
command -v node >/dev/null || fail "node not found. Install Node first (nvm recommended on Linux; brew install node on macOS)."
command -v npm  >/dev/null || fail "npm not found alongside node. Reinstall Node."

NODE_MAJOR="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
if [ "$NODE_MAJOR" -lt 20 ]; then
  warn "Node $(node -v) detected; claude-code + codex officially target Node ≥ 20. Consider upgrading via 'nvm install 22'."
fi

# ─── claude-code ─────────────────────────────────────────────────────────
install_or_upgrade_claude() {
  local pkg="@anthropic-ai/claude-code"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    if command -v claude >/dev/null; then
      ok "claude: $(claude --version 2>/dev/null | head -1)"
    else
      warn "claude: not installed"
    fi
    return
  fi
  if command -v claude >/dev/null; then
    say "Upgrading $pkg..."
  else
    say "Installing $pkg..."
  fi
  if npm install -g "$pkg" >/dev/null 2>&1; then
    ok "$pkg → $(claude --version 2>/dev/null | head -1)"
  else
    fail "npm install -g $pkg failed. Run manually: npm install -g $pkg"
  fi
}

install_or_upgrade_codex() {
  local pkg="@openai/codex"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    if command -v codex >/dev/null; then
      ok "codex: $(codex --version 2>/dev/null | head -1)"
    else
      warn "codex: not installed"
    fi
    return
  fi
  if command -v codex >/dev/null; then
    say "Upgrading $pkg..."
  else
    say "Installing $pkg..."
  fi
  if npm install -g "$pkg" >/dev/null 2>&1; then
    ok "$pkg → $(codex --version 2>/dev/null | head -1)"
  else
    fail "npm install -g $pkg failed. Run manually: npm install -g $pkg"
  fi
}

[ "$SKIP_CLAUDE" -eq 0 ] && install_or_upgrade_claude
[ "$SKIP_CODEX"  -eq 0 ] && install_or_upgrade_codex

if [ "$CHECK_ONLY" -eq 0 ]; then
  cat <<EOF

Runtimes ready. To log in (interactive, do once per machine):

  claude         # then /login   (opens Anthropic OAuth in browser)
  codex login    # opens OpenAI OAuth in browser

Over SSH without browser, both flows print a URL to open on your
laptop. Codex callback uses 127.0.0.1; if your SSH session does not
forward localhost, run with 'ssh -L 1455:localhost:1455 …' first.
EOF
fi
