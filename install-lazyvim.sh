#!/usr/bin/env bash
# Install LazyVim and (if needed) a recent enough Neovim.
# Idempotent: re-running detects existing install and only updates what's missing.
#
# Why this is needed:
#   - LazyVim's latest config requires Neovim ≥ 0.11.
#   - Ubuntu LTS ships an old nvim (0.6 / 0.9). `apt install neovim` is not
#     enough on most LTS releases.
#   - macOS Homebrew has up-to-date nvim, no special handling needed.
#
# What it does:
#   1. Check nvim version.
#   2. If missing or too old:
#        macOS  → brew install neovim
#        Linux  → fetch nvim-linux64 tarball from GitHub releases into
#                 ~/.local/share/nvim-prebuilt/ and symlink ~/.local/bin/nvim
#                 (does NOT touch apt's nvim or sudo for system install)
#   3. Install LazyVim starter into ~/.config/nvim.
#      - If ~/.config/nvim already exists with LazyVim, do nothing.
#      - If ~/.config/nvim has other content, back it up to
#        ~/.config/nvim.bak.<ts> and install fresh.
#   4. Print a hint to run `nvim` once so plugins finish bootstrapping.
#
# Usage:
#   install-lazyvim.sh              # standard install
#   install-lazyvim.sh --no-nvim    # skip nvim install/upgrade (you provide
#                                     a recent enough nvim yourself)
#   install-lazyvim.sh --force      # backup + reinstall LazyVim starter even
#                                     when one is detected

set -euo pipefail

NVIM_MIN_MAJOR=0
NVIM_MIN_MINOR=11
NVIM_RELEASE="${NVIM_RELEASE:-stable}"   # GitHub release tag; "stable" is fine

INSTALL_NVIM=1
FORCE_LAZYVIM=0
for arg in "$@"; do
  case "$arg" in
    --no-nvim) INSTALL_NVIM=0 ;;
    --force)   FORCE_LAZYVIM=1 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
ok()   { printf '✓ %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# ─── Detect platform ─────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      fail "unsupported OS: $OS" ;;
esac

# ─── Check current nvim ──────────────────────────────────────────────────
nvim_version_ok() {
  command -v nvim >/dev/null || return 1
  local ver
  ver="$(nvim --version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//')" || return 1
  local major minor
  major="${ver%%.*}"
  minor="${ver#*.}"; minor="${minor%%.*}"
  if [ "$major" -gt "$NVIM_MIN_MAJOR" ]; then return 0; fi
  if [ "$major" -eq "$NVIM_MIN_MAJOR" ] && [ "$minor" -ge "$NVIM_MIN_MINOR" ]; then return 0; fi
  return 1
}

if nvim_version_ok; then
  ok "nvim $(nvim --version | head -1 | awk '{print $2}') already meets minimum (≥${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR})"
elif [ "$INSTALL_NVIM" -eq 0 ]; then
  fail "nvim is missing or too old; --no-nvim was passed so refusing to install. Either drop --no-nvim or provide nvim ≥ ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR} yourself."
else
  case "$PLATFORM" in
    macos)
      if ! command -v brew >/dev/null; then
        fail "Homebrew not found. Install brew first (https://brew.sh) or rerun with --no-nvim and provide nvim manually."
      fi
      say "Installing latest neovim via brew..."
      brew install neovim || brew upgrade neovim || fail "brew install neovim failed"
      ;;
    linux)
      # Avoid apt — LTS distros ship old nvim. Install GitHub prebuilt to
      # ~/.local/share/nvim-prebuilt and expose via ~/.local/bin/nvim.
      ARCH="$(uname -m)"
      case "$ARCH" in
        x86_64)  TARBALL="nvim-linux-x86_64.tar.gz" ;;
        aarch64) TARBALL="nvim-linux-arm64.tar.gz" ;;
        *) fail "unsupported Linux arch: $ARCH" ;;
      esac
      URL="https://github.com/neovim/neovim/releases/download/${NVIM_RELEASE}/${TARBALL}"
      DST="$HOME/.local/share/nvim-prebuilt"
      BIN="$HOME/.local/bin"
      mkdir -p "$DST" "$BIN"
      say "Fetching neovim $NVIM_RELEASE for $ARCH..."
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT
      if ! curl -fsSL "$URL" -o "$tmp/nvim.tar.gz"; then
        fail "download failed: $URL"
      fi
      tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
      # The tarball extracts to nvim-linux-* / use a stable rename.
      extracted="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'nvim-linux*' | head -1)"
      [ -n "$extracted" ] || fail "could not locate extracted nvim directory"
      rm -rf "$DST"/nvim-current
      mv "$extracted" "$DST"/nvim-current
      ln -sfn "$DST/nvim-current/bin/nvim" "$BIN/nvim"
      ok "installed nvim → $BIN/nvim (target: $DST/nvim-current/bin/nvim)"
      if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN"; then
        warn "$BIN is not on PATH. Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your shell rc."
      fi
      ;;
  esac
  if ! nvim_version_ok; then
    fail "nvim install completed but version is still below ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR}. Investigate manually."
  fi
fi

# ─── LazyVim starter ─────────────────────────────────────────────────────
NVIM_CONFIG="$HOME/.config/nvim"
LAZYVIM_MARKER="$NVIM_CONFIG/lua/config/lazy.lua"
LAZYVIM_REPO="${LAZYVIM_REPO:-https://github.com/LazyVim/starter.git}"

is_lazyvim_starter() {
  [ -f "$LAZYVIM_MARKER" ]
}

if is_lazyvim_starter && [ "$FORCE_LAZYVIM" -eq 0 ]; then
  ok "LazyVim starter already at $NVIM_CONFIG (use --force to reinstall)"
else
  if [ -e "$NVIM_CONFIG" ] || [ -L "$NVIM_CONFIG" ]; then
    backup="$NVIM_CONFIG.bak.$(date +%s)"
    say "backing up existing $NVIM_CONFIG → $(basename "$backup")"
    mv "$NVIM_CONFIG" "$backup"
  fi
  mkdir -p "$(dirname "$NVIM_CONFIG")"
  say "Cloning LazyVim starter..."
  git clone --depth 1 "$LAZYVIM_REPO" "$NVIM_CONFIG"
  rm -rf "$NVIM_CONFIG/.git"
  ok "LazyVim starter installed at $NVIM_CONFIG"
fi

# ─── Stale plugin lockfile cleanup (optional) ────────────────────────────
# If lazy-lock.json was committed at an older Neovim version, plugins may
# refuse to load on first run. We don't auto-delete — but warn so the
# operator knows the recovery path.
if [ -f "$NVIM_CONFIG/lazy-lock.json" ]; then
  ok "lazy-lock.json present — plugins pinned"
fi

cat <<EOF

LazyVim is ready. Next steps:

  1. Run \`nvim\` once. The first launch installs plugins via lazy.nvim;
     wait until you see \`Press any key to continue\`.
  2. Inside nvim, run \`:checkhealth lazyvim\` to verify.
  3. For LSP servers / formatters / linters, run \`:Mason\` and install
     what each language needs (e.g. \`lua-language-server\`, \`prettier\`,
     \`stylua\`, etc.).

Customise via \`~/.config/nvim/lua/plugins/\` and \`~/.config/nvim/lua/config/options.lua\`.
EOF
