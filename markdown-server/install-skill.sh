#!/usr/bin/env bash
# Install the mdurl skill into the current user's Claude/Codex skill dirs.
# This is a manual fallback for users who do not run the repo-level
# install.sh symlink setup. Run as the user, NOT as root.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$DIR/.." && pwd)"
SKILL_SRC="$REPO_DIR/shared/skills/mdurl"
CLAUDE_TARGET="$HOME/.claude/skills/mdurl"
CODEX_TARGET="$HOME/.codex/skills/mdurl"

[[ -f "$SKILL_SRC/SKILL.md" ]] || { echo "missing: $SKILL_SRC/SKILL.md" >&2; exit 1; }

install_skill_link() {
  local target="$1"
  local parent
  parent="$(dirname "$target")"
  if [ -L "$parent" ]; then
    echo "✓ already repo-managed: $parent → $(readlink "$parent")"
    return
  fi
  mkdir -p "$parent"
  ln -sfnT "$SKILL_SRC" "$target"
}

install_skill_link "$CLAUDE_TARGET"
install_skill_link "$CODEX_TARGET"

cat <<EOF
✓ mdurl skill installed:
  $CLAUDE_TARGET → $SKILL_SRC
  $CODEX_TARGET → $SKILL_SRC

Use it from any Claude/Codex session by saying e.g.:
  "open this plan in browser"
  "give me a link to <path>.md"
  "/mdurl <path>"

Sanity check: \`command -v mdurl\` should return /usr/local/bin/mdurl.
If it doesn't, ask an admin to run: sudo bash $DIR/install.sh
EOF
