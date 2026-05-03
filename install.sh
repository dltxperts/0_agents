#!/usr/bin/env bash
# Symlink the Claude Code configuration from this repo into ~/.claude/.
# Idempotent: re-running detects existing correct symlinks and does nothing.
# Safe: backs up real files / directories before replacing.
#
# Usage:
#   install.sh            # Mac / generic: links CLAUDE.md, agents/, lang/
#   install.sh --server   # Server: ALSO links settings.json (wide-permission profile)

set -euo pipefail

SERVER_MODE=0
for arg in "$@"; do
  case "$arg" in
    --server)   SERVER_MODE=1 ;;
    -h|--help)  echo "usage: install.sh [--server]"; exit 0 ;;
    *)          echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC="$REPO_DIR/claude"
DST="$HOME/.claude"

[ -d "$SRC" ] || { echo "ERROR: $SRC not found — is this the 0_agents repo root?"; exit 1; }

mkdir -p "$DST"

link_item() {
  local name="$1"
  local src="$SRC/$name"
  local dst="$DST/$name"

  if [ ! -e "$src" ]; then
    echo "  skip: $src does not exist"
    return
  fi

  if [ -L "$dst" ]; then
    local current
    current=$(readlink "$dst")
    if [ "$current" = "$src" ]; then
      echo "✓ already linked: ~/.claude/$name"
      return
    fi
    echo "  replacing stale symlink ~/.claude/$name (was → $current)"
    rm "$dst"
  elif [ -e "$dst" ]; then
    local backup="${dst}.bak.$(date +%s)"
    echo "  backing up existing ~/.claude/$name → $(basename "$backup")"
    mv "$dst" "$backup"
  fi

  ln -s "$src" "$dst"
  echo "✓ linked: ~/.claude/$name → $src"
}

# Top-level items to symlink. Universal items first; server-only added when --server.
#  agents/ — Task-tool subagents (cops, etc.)
#  skills/ — user-invoked slash commands (/spec, /plan, /review-*, etc.)
#           Format: skills/<name>/SKILL.md
ITEMS=(CLAUDE.md agents skills lang)
if [[ "$SERVER_MODE" -eq 1 ]]; then
  ITEMS+=(settings.json)
  echo "  (server mode: also linking settings.json)"
fi

for item in "${ITEMS[@]}"; do
  link_item "$item"
done

# MCP: register codex (user scope) so any Claude Code session can call it
if command -v claude >/dev/null && command -v codex >/dev/null; then
  if claude mcp list 2>/dev/null | grep -q '^codex:'; then
    echo "✓ codex MCP already registered"
  else
    echo "  Registering codex as user-scope MCP server..."
    if claude mcp add -s user codex -- codex mcp-server >/dev/null 2>&1; then
      echo "✓ codex MCP registered (scope: user)"
    else
      echo "⚠ codex MCP registration failed (continuing)"
    fi
  fi
fi

echo ""
echo "Done. Verify with:  ls -la \"$DST\""
