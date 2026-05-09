#!/usr/bin/env bash
# setup-mdurl.sh -- one-time install of the mdurl markdown server.
#
# Run this ONCE per host, as root. It is independent of setup-server.sh:
# the regular server bootstrap does NOT touch mdurl, so this is opt-in.
#
# What it does (delegates to markdown-server/install.sh):
#   - creates the `mdview` system user (no shell, no home-dir login)
#   - installs python3-markdown if missing
#   - installs `markdown-server` and `mdurl` into /usr/local/bin/
#   - installs the systemd unit and `enable --now`s it
#   - sets up /srv/markdown/ (mode 1777, sticky like /tmp)
#   - smoke-tests http://127.0.0.1:6420/
#
# After this runs, every user on this host can publish via `mdurl <file>`.
# To install the per-user Claude Code skill, each user runs the regular
# `bash ~/Coding/0_agents/update.sh` under their own account.
#
# Usage:
#   sudo bash setup-mdurl.sh             # install
#   sudo bash setup-mdurl.sh uninstall   # tear down (keeps /srv/markdown content)

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  cat >&2 <<EOF
setup-mdurl.sh must run as root. Try:
  sudo bash $0 $*
EOF
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SUBDIR="$DIR/markdown-server"

[[ -x "$SUBDIR/install.sh" ]] || {
  echo "missing: $SUBDIR/install.sh" >&2
  exit 1
}

exec bash "$SUBDIR/install.sh" "$@"
