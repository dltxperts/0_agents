#!/usr/bin/env bash
# Bootstrap a Cyrus coding-agent host on Linux for the current user.
#
# One Cyrus instance, both runners available (claude-code + codex). The
# runner is chosen per-repository in config.json after setup.
#
# This script installs everything from scratch: Node (via nvm), Bun,
# cloudflared, claude-code, codex, and cyrus-ai.
#
# ─── Run AS THE TARGET USER (not root) ──────────────────────────────────────
# If you need a fresh user, do this first as root (one-time):
#
#   sudo adduser vibe
#   sudo loginctl enable-linger vibe        # systemd --user persists at logout
#   sudo -iu vibe                           # become the user
#
# The user must be able to clone from GitHub. Quick path:
#   ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
#   cat ~/.ssh/id_ed25519.pub               # add to github.com/settings/keys
#
# Then:
#   git clone git@github.com:0xmikko/0_agents.git ~/Coding/0_agents
#   bash ~/Coding/0_agents/setup-cyrus.sh
#
# Bare prereqs the OS must already have: bash, curl, git, openssh-client.
# Everything else (Node, Bun, cloudflared, CLIs) is installed by this script.
#
# Optional environment overrides (otherwise prompted):
#   DOMAIN              e.g. mikko.build
#   TUNNEL_NAME         default: $(whoami)  (e.g. vibe, marketing)
#   SUBDOMAIN           default: $TUNNEL_NAME.$DOMAIN
#   PORT                default: existing CYRUS_SERVER_PORT in $ENV_FILE,
#                                otherwise first free port starting at 3456
#   CYRUS_HOME          default: ~/.cyrus
#   NODE_VERSION        default: 20
#   NVM_VERSION         default: v0.40.1

set -euo pipefail

# ─── Config ─────────────────────────────────────────────────────────────────
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CYRUS_HOME="${CYRUS_HOME:-$HOME/.cyrus}"
DOMAIN="${DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-$(whoami)}"
SUBDOMAIN="${SUBDOMAIN:-}"
NODE_VERSION="${NODE_VERSION:-20}"
NVM_VERSION="${NVM_VERSION:-v0.40.1}"
SYSTEMD_DIR="$HOME/.config/systemd/user"
ENV_FILE="$CYRUS_HOME/.env"
CONFIG_FILE="$CYRUS_HOME/config.json"

# Port resolution: explicit $PORT override > value in existing .env >
# first free port starting at 3456. Multiple Cyrus instances on the same
# host (one per agent user) must not collide on the default port.
is_port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$1" 2>/dev/null | tail -n +2 | grep -q .
  else
    (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null
  fi
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

CLOUDFLARED_CONFIG="$HOME/.cloudflared/${TUNNEL_NAME}.yml"
CYRUS_SERVICE="cyrus.service"
TUNNEL_SERVICE="cloudflared-${TUNNEL_NAME}.service"

# ─── Helpers ────────────────────────────────────────────────────────────────
say()    { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
warn()   { printf "\n\033[1;33m⚠ %s\033[0m\n" "$*"; }
ok()     { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
err()    { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }
pause()  { read -rp "  Press Enter when done... " _; }

# ─── 0. Sanity ──────────────────────────────────────────────────────────────
say "Sanity checks"
[[ "$(id -u)" -ne 0 ]] || err "Do NOT run as root. Switch to your agent user (e.g. 'sudo -iu vibe') and rerun."
for c in bash curl git ssh; do
  command -v "$c" >/dev/null || err "$c is missing. Install via your package manager and rerun."
done
ok "running as $(whoami) on $(uname -s) $(uname -m)"

if [[ -z "$DOMAIN" ]]; then
  read -rp "  DOMAIN (e.g. mikko.build): " DOMAIN
  [[ -n "$DOMAIN" ]] || err "DOMAIN is required."
fi
SUBDOMAIN="${SUBDOMAIN:-${TUNNEL_NAME}.${DOMAIN}}"
ok "tunnel target: $TUNNEL_NAME → $SUBDOMAIN  (port $PORT)"

# ─── 1. Node via nvm ────────────────────────────────────────────────────────
say "Node $NODE_VERSION (via nvm)"
if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  ok "nvm $NVM_VERSION installed"
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
if ! command -v node >/dev/null \
     || [[ "$(node -v 2>/dev/null | sed 's/^v//;s/\..*//')" -lt "$NODE_VERSION" ]]; then
  nvm install "$NODE_VERSION"
  nvm alias default "$NODE_VERSION"
fi
nvm use default >/dev/null
ok "node $(node --version), npm $(npm --version)"

# ─── 2. Bun ─────────────────────────────────────────────────────────────────
say "Bun"
if [[ ! -x "$HOME/.bun/bin/bun" ]]; then
  curl -fsSL https://bun.sh/install | bash
fi
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
ok "bun $(bun --version)"

# ─── 3. cloudflared (binary release) ────────────────────────────────────────
say "cloudflared"
if ! command -v cloudflared >/dev/null; then
  case "$(uname -m)" in
    x86_64)        CFD_ARCH=amd64 ;;
    aarch64|arm64) CFD_ARCH=arm64 ;;
    *) err "Unsupported arch $(uname -m) — install cloudflared manually and rerun." ;;
  esac
  mkdir -p "$HOME/.local/bin"
  curl -L --fail \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CFD_ARCH}" \
    -o "$HOME/.local/bin/cloudflared"
  chmod +x "$HOME/.local/bin/cloudflared"
  export PATH="$HOME/.local/bin:$PATH"
fi
ok "cloudflared $(cloudflared --version 2>&1 | head -1)"

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

# ─── 5. Cyrus + runner CLIs (via npm) ───────────────────────────────────────
say "Cyrus and agent runner CLIs"
for pkg in cyrus-ai @anthropic-ai/claude-code @openai/codex; do
  if npm list -g --depth=0 "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    npm install -g "$pkg"
    ok "$pkg installed"
  fi
done

CYRUS_BIN="$(command -v cyrus)"
CLOUDFLARED_BIN="$(command -v cloudflared)"
NODE_DIR="$(dirname "$(readlink -f "$(command -v node)")")"
NPM_GLOBAL_BIN="$(npm prefix -g)/bin"
BUN_DIR="$HOME/.bun/bin"
LOCAL_BIN="$HOME/.local/bin"

# ─── 6. Symlink ~/.claude/ from this repo ───────────────────────────────────
if [ -x "$REPO_DIR/install.sh" ]; then
  say "Linking ~/.claude/ from $REPO_DIR/claude (server mode — includes settings.json)"
  bash "$REPO_DIR/install.sh" --server
else
  warn "install.sh not found alongside this script — skipping ~/.claude/ link"
fi

# ─── 6b. Subscription logins for both runners ───────────────────────────────
# Both runners authenticate via Anthropic / OpenAI subscriptions, not API
# keys. Each CLI prints a URL — open it on any device with a browser.

say "Claude Code subscription login"
if [[ -f "$HOME/.claude/.credentials.json" ]]; then
  ok "claude-code already authenticated ($HOME/.claude/.credentials.json present)"
else
  echo "  Running 'claude setup-token' — open the printed URL, sign in, paste back."
  claude setup-token \
    || warn "setup-token failed; finish manually: run 'claude' then '/login'"
fi

say "Codex subscription login"
if [[ -f "$HOME/.codex/auth.json" ]]; then
  ok "codex already authenticated ($HOME/.codex/auth.json present)"
else
  codex login \
    || warn "codex login exited non-zero — retry with 'codex login'"
fi

# ─── 7. Cyrus home ──────────────────────────────────────────────────────────
say "Cyrus home: $CYRUS_HOME"
mkdir -p "$CYRUS_HOME"

# ─── 8. Cloudflare Tunnel ───────────────────────────────────────────────────
say "Cloudflare Tunnel: $TUNNEL_NAME → $SUBDOMAIN"
if cloudflared tunnel list 2>/dev/null | awk '{print $2}' | grep -qx "$TUNNEL_NAME"; then
  ok "Tunnel $TUNNEL_NAME already exists, reusing"
  TUNNEL_UUID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$TUNNEL_NAME" '$2==n {print $1}')
else
  cloudflared tunnel create "$TUNNEL_NAME"
  TUNNEL_UUID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$TUNNEL_NAME" '$2==n {print $1}')
  cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"
  ok "Tunnel created, UUID: $TUNNEL_UUID"
fi

cat > "$CLOUDFLARED_CONFIG" <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $HOME/.cloudflared/${TUNNEL_UUID}.json

ingress:
  - hostname: $SUBDOMAIN
    service: http://localhost:$PORT
  - service: http_status:404
EOF
ok "Tunnel config: $CLOUDFLARED_CONFIG"

# ─── 9. Env file (Linear OAuth + API keys) ──────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  ok "$ENV_FILE already exists, reusing (delete it to redo this step)"
else
  say "MANUAL STEP: create a Linear OAuth Application"
  cat <<EOF
  Open: https://linear.app/settings/api/applications/new
    Name             : $(whoami)
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

# ─── 10. systemd --user units ───────────────────────────────────────────────
say "Installing systemd --user units"
mkdir -p "$SYSTEMD_DIR"

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

# ─── 11. Start tunnel ───────────────────────────────────────────────────────
say "Starting tunnel"
systemctl --user enable --now "$TUNNEL_SERVICE"
sleep 3
systemctl --user --quiet is-active "$TUNNEL_SERVICE" \
  || err "Tunnel failed: journalctl --user -u $TUNNEL_SERVICE -n 50"
ok "Tunnel active"

# ─── 12. Cyrus self-auth-linear (interactive browser) ───────────────────────
say "Authenticating Cyrus with Linear (browser flow)"
echo "  cyrus will print a URL — open it in your browser and authorize."
echo
set -a; source "$ENV_FILE"; set +a
"$CYRUS_BIN" --cyrus-home "$CYRUS_HOME" --env-file "$ENV_FILE" self-auth-linear \
  || warn "self-auth-linear exited non-zero; if you completed the browser flow, ignore"

# ─── 13. Add a repository ───────────────────────────────────────────────────
say "Adding a repository (interactive)"
echo "  Use SSH URL: git@github.com:owner/repo.git"
echo "  When prompted for runner, choose claude or codex per the repo's needs."
echo
"$CYRUS_BIN" --cyrus-home "$CYRUS_HOME" --env-file "$ENV_FILE" self-add-repo \
  || warn "self-add-repo exited non-zero"

# ─── 14. Per-repo runner config (manual hint) ───────────────────────────────
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

# ─── 15. Start Cyrus ────────────────────────────────────────────────────────
say "Starting Cyrus"
systemctl --user enable --now "$CYRUS_SERVICE"
sleep 3
systemctl --user --quiet is-active "$CYRUS_SERVICE" \
  || err "Cyrus failed: journalctl --user -u $CYRUS_SERVICE -n 50"
ok "Cyrus active"

# ─── 16. Clean up cloudflared origin cert ───────────────────────────────────
# cert.pem authorizes creating new tunnels and modifying DNS for the zone —
# powerful credential. The running tunnel uses per-tunnel JSON, not cert.pem,
# so removing it after setup doesn't disrupt anything. Re-run
# `cloudflared tunnel login` if you need to add another tunnel later.
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
  Toolchain     : node $(node --version), bun $(bun --version), cyrus $(cyrus --version 2>/dev/null || echo unknown)

  Test: assign a Linear issue to your bot user and watch the logs.

  Note: cloudflared origin cert (cert.pem) was removed for safety. The
  running tunnel keeps working via its per-tunnel credentials. To add
  another tunnel or modify DNS, re-run 'cloudflared tunnel login'.
EOF
