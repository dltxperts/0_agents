#!/usr/bin/env bash
# Install the mdurl Claude Code skill into the current user's
# ~/.claude/skills/ directory. Run as the user, NOT as root.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$DIR/SKILL.md"
TARGET="$HOME/.claude/skills/mdurl"

[[ -f "$SKILL_SRC" ]] || { echo "missing: $SKILL_SRC" >&2; exit 1; }

mkdir -p "$TARGET"
# symlink so future repo updates propagate without re-running this
ln -sfT "$SKILL_SRC" "$TARGET/SKILL.md"

cat <<EOF
✓ mdurl skill installed at $TARGET/SKILL.md (symlink → $SKILL_SRC)

Use it from any Claude Code session by saying e.g.:
  "open this plan in browser"
  "give me a link to <path>.md"
  "/mdurl <path>"

Sanity check: \`command -v mdurl\` should return /usr/local/bin/mdurl.
If it doesn't, ask an admin to run: sudo bash $DIR/install.sh
EOF
