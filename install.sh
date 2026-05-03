#!/usr/bin/env bash
# Symlink the Claude Code configuration from this repo into ~/.claude/.
# Idempotent: re-running detects existing correct symlinks and does nothing.
# Safe: backs up real files / directories before replacing.

set -euo pipefail

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

# Top-level items to symlink. Add new ones here when the repo gains content.
for item in CLAUDE.md agents lang; do
  link_item "$item"
done

echo ""
echo "Done. Verify with:  ls -la \"$DST\""
