#!/usr/bin/env bash
# Set up Cyrus on this host. Cyrus-only — assumes the server is already
# bootstrapped (Node, Bun, cloudflared, claude-code, codex installed).
#
# If the prerequisites aren't there, this script STOPS and tells you to
# run setup-server.sh first. Do not duplicate server bootstrap here.
#
# What this does (Cyrus-only):
#   1. Pre-flight: verify setup-server.sh has run
#   2. Install cyrus-ai npm CLI
#   3. cloudflared login (interactive — needed once per zone)
#   4. Cyrus home (~/.cyrus)
#   5. Cloudflare tunnel + DNS route + tunnel config file
#   6. Env file (Linear OAuth Application secrets)
#   7. systemd --user units (cyrus.service + cloudflared-<bot>.service)
#   8. Start tunnel
#   9. cyrus self-auth-linear (browser flow)
#  10. cyrus self-add-repo (interactive)
#  11. Per-repo runner config hint
#  12. Start cyrus
#  13. Clean up cloudflared origin cert
#
# Run AS THE TARGET USER, not root.
#
# Optional env overrides (otherwise prompted):
#   DOMAIN              e.g. mikko.build
#   TUNNEL_NAME         default: $(whoami)-bot
#   SUBDOMAIN           default: $TUNNEL_NAME.$DOMAIN
#   PORT                default: existing CYRUS_SERVER_PORT in $ENV_FILE,
#                                otherwise first free port starting at 3456
#   CYRUS_HOME          default: ~/.cyrus

set -euo pipefail

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CYRUS_HOME="${CYRUS_HOME:-$HOME/.cyrus}"
DOMAIN="${DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-$(whoami)-bot}"
SUBDOMAIN="${SUBDOMAIN:-}"
SYSTEMD_DIR="$HOME/.config/systemd/user"
ENV_FILE="$CYRUS_HOME/.env"
CONFIG_FILE="$CYRUS_HOME/config.json"

say()    { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
warn()   { printf "\n\033[1;33m⚠ %s\033[0m\n" "$*"; }
ok()     { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
err()    { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }
pause()  { read -rp "  Press Enter when done... " _; }

# ─── 1. Pre-flight: server bootstrapped? ────────────────────────────────────
say "Pre-flight: checking that setup-server.sh has run"
[[ "$(id -u)" -ne 0 ]] || err "Do NOT run as root."

missing=()
for c in node npm bun cloudflared claude codex; do
  command -v "$c" >/dev/null || missing+=("$c")
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  err "Missing prerequisites: ${missing[*]}. Run 'bash $REPO_DIR/setup-server.sh' first, then come back."
fi
ok "node $(node --version), bun $(bun --version), cloudflared OK, claude OK, codex OK"

[[ -L "$HOME/.claude/CLAUDE.md" ]] \
  || warn "~/.claude/CLAUDE.md not symlinked — agent config may be stale. Run setup-server.sh."

# ─── 2. Cyrus npm CLI ───────────────────────────────────────────────────────
say "Cyrus CLI"
if npm list -g --depth=0 cyrus-ai >/dev/null 2>&1; then
  ok "cyrus-ai already installed"
else
  npm install -g cyrus-ai
  ok "cyrus-ai installed"
fi
CYRUS_BIN="$(command -v cyrus)"
ok "cyrus $(cyrus --version 2>/dev/null || echo unknown) at $CYRUS_BIN"

# ─── 3. Tunnel target prompts ───────────────────────────────────────────────
if [[ -z "$DOMAIN" ]]; then
  read -rp "  DOMAIN (e.g. mikko.build): " DOMAIN
  [[ -n "$DOMAIN" ]] || err "DOMAIN is required."
fi
SUBDOMAIN="${SUBDOMAIN:-${TUNNEL_NAME}.${DOMAIN}}"

# Port resolution: explicit $PORT > existing in ENV_FILE > first free starting at 3456
is_port_in_use() {
  (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && return 0
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$1" 2>/dev/null | tail -n +2 | grep -q . && return 0
  fi
  return 1
}
find_free_port() {
  local p=$1
  while is_port_in_use "$p"; do p=$((p + 1)); done
  echo "$p"
}
if [[ -z "${PORT:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    PORT="$(awk -F= '$1=="CYRUS_SERVER_PORT"{print $2; exit}' "$ENV_FILE" | tr -d '[:space:]')"
  fi
  PORT="${PORT:-$(find_free_port 3456)}"
fi
ok "tunnel target: $TUNNEL_NAME → $SUBDOMAIN  (port $PORT)"

CLOUDFLARED_CONFIG="$HOME/.cloudflared/${TUNNEL_NAME}.yml"
CYRUS_SERVICE="cyrus.service"
TUNNEL_SERVICE="cloudflared-${TUNNEL_NAME}.service"

# ─── 4. cloudflared login (interactive) ─────────────────────────────────────
if [[ ! -f "$HOME/.cloudflared/cert.pem" ]]; then
  warn "cloudflared not logged in. Starting browser auth flow now."
  echo "  cloudflared will print a URL — open it on any device with a browser,"
  echo "  log in, and authorize the '$DOMAIN' zone. This terminal will unblock"
  echo "  automatically once the cert is delivered."
  cloudflared tunnel login
  [[ -f "$HOME/.cloudflared/cert.pem" ]] \
    || err "Login finished but no cert.pem appeared. Try manually: cloudflared tunnel login"
fi
ok "cloudflared logged in"

# ─── 5. Cyrus home + tunnel + DNS ───────────────────────────────────────────
say "Cyrus home: $CYRUS_HOME"
mkdir -p "$CYRUS_HOME"

say "Cloudflare Tunnel: $TUNNEL_NAME → $SUBDOMAIN"
if cloudflared tunnel list 2>/dev/null | awk '{print $2}' | grep -qx "$TUNNEL_NAME"; then
  ok "Tunnel $TUNNEL_NAME already exists, reusing"
  TUNNEL_UUID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$TUNNEL_NAME" '$2==n {print $1}')
else
  cloudflared tunnel create "$TUNNEL_NAME"
  TUNNEL_UUID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$TUNNEL_NAME" '$2==n {print $1}')
  ok "Tunnel created, UUID: $TUNNEL_UUID"
fi

if cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN" 2>&1 | tee /tmp/cfd-route.$$; then
  ok "DNS route asserted: $SUBDOMAIN → ${TUNNEL_UUID}.cfargotunnel.com"
else
  if grep -qiE 'already exists|points to' /tmp/cfd-route.$$; then
    ok "DNS route already in place for $SUBDOMAIN"
  else
    warn "DNS route assertion failed — create CNAME manually: $SUBDOMAIN → ${TUNNEL_UUID}.cfargotunnel.com (proxied)"
  fi
fi
rm -f /tmp/cfd-route.$$

cat > "$CLOUDFLARED_CONFIG" <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $HOME/.cloudflared/${TUNNEL_UUID}.json

ingress:
  - hostname: $SUBDOMAIN
    service: http://localhost:$PORT
  - service: http_status:404
EOF
ok "Tunnel config: $CLOUDFLARED_CONFIG"

# ─── 6. Env file (Linear OAuth Application) ─────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  ok "$ENV_FILE already exists, reusing (delete it to redo this step)"
else
  say "MANUAL STEP: create a Linear OAuth Application"
  cat <<EOF
  Open: https://linear.app/settings/api/applications/new
    Name             : $(whoami)-bot
    Developer URL    : https://github.com/cyrusagents/cyrus
    Callback URLs    : https://$SUBDOMAIN/callback
    Webhook URL      : https://$SUBDOMAIN/linear-webhook
    Webhook events   : Issues, Issue Labels, Comments, Issue attachments,
                       Agent session events, Inbox notifications
    Scopes           : read, write, app:assignable, app:mentionable
  Save and copy the three secrets below.
EOF
  pause

  read -rp  "  LINEAR_CLIENT_ID:                            " LINEAR_CLIENT_ID
  read -rp  "  LINEAR_CLIENT_SECRET:                        " LINEAR_CLIENT_SECRET
  read -rp  "  LINEAR_WEBHOOK_SECRET:                       " LINEAR_WEBHOOK_SECRET

  umask 077
  {
    echo "LINEAR_DIRECT_WEBHOOKS=true"
    echo "CYRUS_BASE_URL=https://$SUBDOMAIN"
    echo "CYRUS_SERVER_PORT=$PORT"
    echo "LINEAR_CLIENT_ID=$LINEAR_CLIENT_ID"
    echo "LINEAR_CLIENT_SECRET=$LINEAR_CLIENT_SECRET"
    echo "LINEAR_WEBHOOK_SECRET=$LINEAR_WEBHOOK_SECRET"
  } > "$ENV_FILE"
  umask 022
  ok "Wrote $ENV_FILE (chmod 600)"
fi

[[ -f "$CONFIG_FILE" ]] || echo '{"repositories": []}' > "$CONFIG_FILE"
ok "Config: $CONFIG_FILE"

# ─── 7. systemd --user units ────────────────────────────────────────────────
say "Installing systemd --user units"
mkdir -p "$SYSTEMD_DIR"

CLOUDFLARED_BIN="$(command -v cloudflared)"
NODE_DIR="$(dirname "$(readlink -f "$(command -v node)")")"
NPM_GLOBAL_BIN="$(npm prefix -g)/bin"
BUN_DIR="$HOME/.bun/bin"
LOCAL_BIN="$HOME/.local/bin"
UNIT_PATH="$NPM_GLOBAL_BIN:$NODE_DIR:$BUN_DIR:$LOCAL_BIN:/usr/local/bin:/usr/bin:/bin"

cat > "$SYSTEMD_DIR/$TUNNEL_SERVICE" <<EOF
[Unit]
Description=Cloudflare Tunnel ($TUNNEL_NAME)
After=network.target

[Service]
Type=simple
ExecStart=$CLOUDFLARED_BIN tunnel --config $CLOUDFLARED_CONFIG run $TUNNEL_NAME
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

cat > "$SYSTEMD_DIR/$CYRUS_SERVICE" <<EOF
[Unit]
Description=Cyrus coding agent
After=network.target $TUNNEL_SERVICE
Requires=$TUNNEL_SERVICE

[Service]
Type=simple
Environment="PATH=$UNIT_PATH"
EnvironmentFile=$ENV_FILE
ExecStart=$CYRUS_BIN --cyrus-home $CYRUS_HOME --env-file $ENV_FILE
Restart=on-failure
RestartSec=10
MemoryMax=4G

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
ok "Units installed"

# ─── 8. Start tunnel ────────────────────────────────────────────────────────
say "Starting tunnel"
systemctl --user enable --now "$TUNNEL_SERVICE"
sleep 3
systemctl --user --quiet is-active "$TUNNEL_SERVICE" \
  || err "Tunnel failed: journalctl --user -u $TUNNEL_SERVICE -n 50"
ok "Tunnel active"

# ─── 9. cyrus self-auth-linear ──────────────────────────────────────────────
say "Authenticating Cyrus with Linear (browser flow)"
echo "  cyrus will print a URL — open it in your browser and authorize."
echo
set -a; source "$ENV_FILE"; set +a
"$CYRUS_BIN" --cyrus-home "$CYRUS_HOME" --env-file "$ENV_FILE" self-auth-linear \
  || warn "self-auth-linear exited non-zero; if you completed the browser flow, ignore"

# ─── 10. cyrus self-add-repo ────────────────────────────────────────────────
say "Adding a repository (interactive)"
echo "  Use SSH URL: git@github.com:owner/repo.git"
echo "  When prompted for runner, choose claude or codex per the repo's needs."
echo
"$CYRUS_BIN" --cyrus-home "$CYRUS_HOME" --env-file "$ENV_FILE" self-add-repo \
  || warn "self-add-repo exited non-zero"

# ─── 11. Per-repo runner config hint ────────────────────────────────────────
say "Per-repo runner configuration"
cat <<EOF
  Cyrus stores per-repo settings in: $CONFIG_FILE
  In each repository entry you can set the runner explicitly:

      "runner": "claude"     # uses claude-code CLI + ANTHROPIC_API_KEY
      "runner": "codex"      # uses codex CLI + OPENAI_API_KEY

  Optional team filter (only handle issues for one Linear team):
      "teamKeys": ["YOUR_TEAM_KEY"]

  Cyrus watches config.json and reloads on change.
EOF

# ─── 12. Start Cyrus ────────────────────────────────────────────────────────
say "Starting Cyrus"
systemctl --user enable --now "$CYRUS_SERVICE"
sleep 3
systemctl --user --quiet is-active "$CYRUS_SERVICE" \
  || err "Cyrus failed: journalctl --user -u $CYRUS_SERVICE -n 50"
ok "Cyrus active"

# ─── 13. Clean up cloudflared origin cert ───────────────────────────────────
say "Removing cloudflared origin cert"
cloudflared tunnel logout 2>/dev/null || true
if [[ -f "$HOME/.cloudflared/cert.pem" ]]; then
  warn "cert.pem still present after logout — remove manually if you want"
else
  ok "cert.pem removed (running tunnel keeps using per-tunnel credentials)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
say "Done."
cat <<EOF
  Cyrus home    : $CYRUS_HOME
  Public URL    : https://$SUBDOMAIN
  Local port    : $PORT
  Services      : $CYRUS_SERVICE, $TUNNEL_SERVICE
  Logs          : journalctl --user -u $CYRUS_SERVICE -f
  Config        : $CONFIG_FILE
  Env           : $ENV_FILE   (chmod 600)

  Test: assign a Linear issue to your bot user and watch the logs.

  Note: cloudflared origin cert (cert.pem) was removed for safety. The
  running tunnel keeps working via its per-tunnel credentials. To add
  another tunnel or modify DNS, re-run 'cloudflared tunnel login'.
EOF
