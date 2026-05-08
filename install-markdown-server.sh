#!/usr/bin/env bash
# Install / update the mdurl markdown-server.
#
# Two halves:
#   * server-side  -- runs `markdown-server/install.sh` under sudo. Creates
#                     mdview system user, drops binaries, enables systemd unit.
#                     Only run on hosts that should serve mdurl (--server).
#   * per-user     -- runs `markdown-server/install-skill.sh` for the current
#                     user. Symlinks the Claude Code skill into
#                     ~/.claude/skills/mdurl/SKILL.md.
#
# Both halves are idempotent.
#
# Usage:
#   install-markdown-server.sh           # per-user skill only
#   install-markdown-server.sh --server  # also install/update the server (sudo)
#   install-markdown-server.sh --no-skill   # only the server, skip the skill
#
# Invoked from update.sh and setup-server.sh; safe to run by hand.

set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SUBDIR="$REPO_DIR/markdown-server"

DO_SERVER=0
DO_SKILL=1
for arg in "$@"; do
  case "$arg" in
    --server)   DO_SERVER=1 ;;
    --no-skill) DO_SKILL=0 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "install-markdown-server.sh: unknown flag: $arg" >&2; exit 2 ;;
  esac
done

[[ -d "$SUBDIR" ]] || { echo "missing: $SUBDIR" >&2; exit 1; }

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*" >&2; }

# ─── server side ────────────────────────────────────────────────────────────
if [[ "$DO_SERVER" -eq 1 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    warn "sudo not available; cannot run server-side install"
    exit 1
  fi
  printf '\n\033[1;36m▶ markdown-server: server-side install (sudo)\033[0m\n'
  sudo bash "$SUBDIR/install.sh"
fi

# ─── per-user skill ─────────────────────────────────────────────────────────
if [[ "$DO_SKILL" -eq 1 ]]; then
  if [[ -x "$SUBDIR/install-skill.sh" ]]; then
    printf '\n\033[1;36m▶ markdown-server: per-user Claude skill\033[0m\n'
    bash "$SUBDIR/install-skill.sh"
  else
    warn "missing: $SUBDIR/install-skill.sh"
  fi
fi

ok "install-markdown-server.sh done"
