#!/usr/bin/env bash
# Register Linear MCP for Codex and Claude Code.
# Auth is OAuth-based. Codex login is attempted after registration.

set -euo pipefail

LINEAR_MCP_URL="${LINEAR_MCP_URL:-https://mcp.linear.app/mcp}"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'EOF'
usage: install-linear-mcp.sh

Registers Linear MCP for:
  - Codex:      codex mcp add linear --url https://mcp.linear.app/mcp
  - Claude:     claude mcp add -s user --transport http linear https://mcp.linear.app/mcp

After registration, runs on local/non-SSH sessions:
  codex mcp login linear

Over SSH, Codex OAuth needs an ssh -L tunnel because the callback redirects
to 127.0.0.1 on the server. The script prints the required steps instead of
starting a broken localhost callback.

Claude Code handles HTTP MCP OAuth on first use. Cyrus Linear OAuth is separate:
  cyrus --cyrus-home ~/.cyrus --env-file ~/.cyrus/.env self-auth-linear
EOF
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

say() { printf "\n▶ %s\n" "$*"; }
ok() { printf "  ✓ %s\n" "$*"; }
warn() { printf "  ⚠ %s\n" "$*" >&2; }
is_ssh_session() { [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]]; }

say "Linear MCP endpoint: $LINEAR_MCP_URL"

if command -v codex >/dev/null 2>&1; then
  say "Codex MCP"
  echo "  checking: codex mcp get linear"
  if codex mcp get linear; then
    ok "codex MCP 'linear' already registered"
  else
    echo "  running: codex mcp add linear --url $LINEAR_MCP_URL"
    if codex mcp add linear --url "$LINEAR_MCP_URL"; then
      ok "registered codex MCP 'linear'"
    else
      warn "failed to register codex MCP 'linear'"
    fi
  fi
  say "Codex Linear OAuth"
  if is_ssh_session; then
    warn "SSH detected; codex OAuth redirects to 127.0.0.1 on this server."
    echo "  MCP entry is installed. To finish Codex OAuth over SSH:"
    echo "    1. Run manually: codex mcp login linear"
    echo "    2. Copy the printed localhost callback port from redirect_uri."
    echo "    3. On your Mac, open another terminal:"
    echo "       ssh -L <port>:127.0.0.1:<port> <user>@<server>"
    echo "    4. Open the printed Linear authorize URL in your Mac browser."
  else
    echo "  running: codex mcp login linear"
    if codex mcp login linear; then
      ok "codex MCP 'linear' authenticated"
    else
      warn "codex MCP 'linear' login did not complete; retry with: codex mcp login linear"
    fi
  fi
else
  warn "codex not found; skipping Codex MCP"
fi

if command -v claude >/dev/null 2>&1; then
  say "Claude MCP"
  echo "  checking: claude mcp get linear"
  if claude mcp get linear; then
    ok "claude MCP 'linear' already registered"
  else
    echo "  running: claude mcp add -s user --transport http linear $LINEAR_MCP_URL"
    if claude mcp add -s user --transport http linear "$LINEAR_MCP_URL"; then
      ok "registered claude MCP 'linear' (scope: user)"
    else
      warn "failed to register claude MCP 'linear'"
    fi
  fi
  echo "  Auth is handled by Claude Code when the HTTP MCP server requests OAuth."
else
  warn "claude not found; skipping Claude MCP"
fi
