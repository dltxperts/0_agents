#!/usr/bin/env bash
# Install mdurl markdown-server (run as root).
#
# Creates the mdview system user, installs server.py + mdurl + systemd unit,
# sets up /srv/markdown, then enables and starts the service.
#
# Usage:
#   sudo bash install.sh           # install
#   sudo bash install.sh uninstall # tear down (keeps /srv/markdown content)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
MDURL_ROOT_DIR="${MDURL_ROOT:-/srv/markdown}"
SVC_USER=mdview
SVC_GROUP=mdview
SVC_HOME=/var/lib/mdview

say() { printf "\n\033[1;36m== %s\033[0m\n" "$*"; }
ok()  { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn(){ printf "  \033[1;33m!\033[0m %s\n" "$*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "must run as root: sudo bash $0" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# Uninstall path
# --------------------------------------------------------------------------- #
if [[ "${1:-install}" == "uninstall" ]]; then
  say "Uninstalling markdown-server"
  systemctl disable --now markdown-server.service 2>/dev/null || true
  rm -f /etc/systemd/system/markdown-server.service
  rm -f /usr/local/bin/markdown-server /usr/local/bin/mdurl
  systemctl daemon-reload
  ok "service removed"
  warn "user '$SVC_USER' and '$MDURL_ROOT_DIR' content kept (delete by hand if you want)"
  exit 0
fi

# --------------------------------------------------------------------------- #
# Install path
# --------------------------------------------------------------------------- #
say "Installing mdurl markdown-server"

# 1. system user
if ! id "$SVC_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin --home "$SVC_HOME" "$SVC_USER"
  install -d -o "$SVC_USER" -g "$SVC_GROUP" -m 700 "$SVC_HOME"
  ok "created system user '$SVC_USER'"
else
  ok "system user '$SVC_USER' already exists"
fi

# 2. python markdown lib
if ! python3 -c 'import markdown' 2>/dev/null; then
  apt-get update
  apt-get install -y python3-markdown
fi
ok "python3-markdown present"

# 3. /srv/markdown -- world-writable + sticky so users can publish their own
install -d -o root -g root -m 1777 "$MDURL_ROOT_DIR"
ok "$MDURL_ROOT_DIR ready (mode 1777, sticky)"

# 4. binaries
install -o root -g root -m 755 "$DIR/server.py" /usr/local/bin/markdown-server
install -o root -g root -m 755 "$DIR/mdurl" /usr/local/bin/mdurl
ok "/usr/local/bin/markdown-server, /usr/local/bin/mdurl installed"

# 5. systemd unit
install -o root -g root -m 644 \
  "$DIR/markdown-server.service" /etc/systemd/system/markdown-server.service
systemctl daemon-reload
systemctl enable --now markdown-server.service
ok "systemd unit enabled and started"

# 6. sanity check
sleep 1
if ! systemctl is-active --quiet markdown-server.service; then
  warn "service is not active; logs:"
  journalctl -u markdown-server.service -n 20 --no-pager
  exit 1
fi
PORT="${MARKDOWN_PORT:-6420}"
HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${PORT}/" || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "service listening on :${PORT} (HTTP $HTTP_CODE)"
else
  warn "service is up but / returned HTTP $HTTP_CODE; check journalctl"
fi

cat <<EOF

================================================================
  installed!

  service:   systemctl status markdown-server
  CLI:       mdurl --help
  base URL:  http://u3775:${PORT}/

  any user on this machine can now publish a doc:
      mdurl ~/path/to/file.md
      # -> http://u3775:${PORT}/<their-username>/<slug>

  per-user Claude skill:
      bash $DIR/install-skill.sh
================================================================
EOF
