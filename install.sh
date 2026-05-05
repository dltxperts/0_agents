#!/usr/bin/env bash
# Symlink agent configuration from this repo into ~/.claude/ and ~/.codex/
# and install shared helper scripts into ~/.local/bin.
# Idempotent: re-running detects existing correct symlinks and does nothing.
# Safe: backs up real files / directories before replacing.
#
# Usage:
#   install.sh            # Mac / generic: links Claude + Codex shared config
#   install.sh --server   # Server: ALSO links settings.json (wide-permission profile)

set -euo pipefail

SERVER_MODE=0
while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --server)
      SERVER_MODE=1
      shift
      ;;
    -h|--help)
      echo "usage: install.sh [--server]"
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLAUDE_SRC="$REPO_DIR/claude"
CODEX_SRC="$REPO_DIR/codex"
SHARED_SRC="$REPO_DIR/shared"
CLAUDE_DST="$HOME/.claude"
CODEX_DST="$HOME/.codex"

[ -d "$CLAUDE_SRC" ] || { echo "ERROR: $CLAUDE_SRC not found — is this the 0_agents repo root?"; exit 1; }
[ -d "$CODEX_SRC" ] || { echo "ERROR: $CODEX_SRC not found — is this the 0_agents repo root?"; exit 1; }
[ -d "$SHARED_SRC/lang" ] || { echo "ERROR: $SHARED_SRC/lang not found — is this the 0_agents repo root?"; exit 1; }

mkdir -p "$CLAUDE_DST" "$CODEX_DST"

link_item() {
  local label="$1"
  local src="$2"
  local dst="$3"

  if [ ! -e "$src" ]; then
    echo "  skip: $src does not exist"
    return
  fi

  if [ -L "$dst" ]; then
    local current
    current=$(readlink "$dst")
    if [ "$current" = "$src" ]; then
      echo "✓ already linked: $label"
      return
    fi
    echo "  replacing stale symlink $label (was → $current)"
    rm "$dst"
  elif [ -e "$dst" ]; then
    local backup="${dst}.bak.$(date +%s)"
    echo "  backing up existing $label → $(basename "$backup")"
    mv "$dst" "$backup"
  fi

  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "✓ linked: $label → $src"
}

link_codex_skill() {
  local skill_name="$1"
  local src="$CODEX_SRC/skills/$skill_name"
  local dst="$CODEX_DST/skills/$skill_name"
  local label="~/.codex/skills/$skill_name"

  if [ -L "$dst" ]; then
    local current
    current=$(readlink "$dst")
    if [ "$current" = "$src" ]; then
      echo "✓ already linked: $label"
      return
    fi
    case "$current" in
      "$CODEX_SRC"/skills/*)
        echo "  replacing stale general codex skill symlink $label (was → $current)"
        rm "$dst"
        ;;
      *)
        echo "  keep existing codex skill: $label (→ $current)"
        return
        ;;
    esac
  elif [ -e "$dst" ]; then
    echo "  keep existing codex skill: $label"
    return
  fi

  ln -s "$src" "$dst"
  echo "✓ linked: $label → $src"
}

# Claude top-level items. `lang/` and common skills are symlinks into `shared/`.
#  agents/ — Task-tool subagents (cops, etc.)
#  skills/ — user-invoked slash commands (/spec, /plan, /review-*, etc.)
#           Format: skills/<name>/SKILL.md
CLAUDE_ITEMS=(CLAUDE.md agents skills)
if [[ "$SERVER_MODE" -eq 1 ]]; then
  CLAUDE_ITEMS+=(settings.json)
  echo "  (server mode: also linking settings.json)"
fi

for item in "${CLAUDE_ITEMS[@]}"; do
  link_item "~/.claude/$item" "$CLAUDE_SRC/$item" "$CLAUDE_DST/$item"
done
link_item "~/.claude/lang" "$SHARED_SRC/lang" "$CLAUDE_DST/lang"

# Codex skills live next to system skills in ~/.codex/skills/.system, so link
# individual skill directories instead of replacing ~/.codex/skills. Project
# skills with the same name are resolved by Codex's normal project override.
mkdir -p "$CODEX_DST/skills"
for skill_dir in "$CODEX_SRC"/skills/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  link_codex_skill "$skill_name"
done
link_item "~/.codex/agents" "$CODEX_SRC/agents" "$CODEX_DST/agents"
link_item "~/.codex/lang" "$SHARED_SRC/lang" "$CODEX_DST/lang"

if [ -x "$REPO_DIR/install-bin.sh" ]; then
  bash "$REPO_DIR/install-bin.sh"
fi

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
echo "Done. Verify with:  ls -la \"$CLAUDE_DST\" \"$CODEX_DST/skills\" \"$HOME/.local/bin\""
