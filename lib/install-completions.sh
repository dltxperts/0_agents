#!/usr/bin/env bash
# Generate zsh completion files for installed CLI tools and wire them into ~/.zshrc.
# Idempotent: regenerates files in place, only writing when content changed; the
# block in ~/.zshrc is delimited by markers so re-runs replace cleanly.
#
# Tools probed (only those present on PATH get a completion file):
#   zellij   — zellij setup --generate-completion zsh
#   gh       — gh completion -s zsh
#   codex    — codex completion zsh
#   bun      — bun completions
#   rg       — rg --generate complete-zsh
#   docker   — docker completion zsh
#   kubectl  — kubectl completion zsh
#   helm     — helm completion zsh
#   cargo    — rustup completions zsh cargo (if rustup present)
#   rustup   — rustup completions zsh
#
# claude-code and cloudflared do not ship completions and are intentionally skipped.

set -euo pipefail

COMP_DIR="$HOME/.zsh/completions"
ZSHRC="$HOME/.zshrc"
MARK_BEGIN='# >>> 0_agents completions >>>'
MARK_END='# <<< 0_agents completions <<<'

mkdir -p "$COMP_DIR"

# generate <name> <command...>
# Captures stdout of the command and writes it to $COMP_DIR/_<name> only if
# the content changed. Silent skip if the first command is missing.
generate() {
  local name="$1"; shift
  local out_file="$COMP_DIR/_$name"

  if ! command -v "$1" >/dev/null 2>&1; then
    echo "  skip _$name: $1 not installed"
    return
  fi

  local content
  if ! content="$("$@" 2>/dev/null)" || [[ -z "$content" ]]; then
    echo "  skip _$name: '$*' produced no output"
    return
  fi

  if [[ -f "$out_file" ]] && [[ "$content" == "$(cat "$out_file")" ]]; then
    echo "✓ up to date: _$name"
    return
  fi
  printf '%s\n' "$content" > "$out_file"
  echo "✓ wrote: _$name ($(printf '%s\n' "$content" | wc -l) lines)"
}

generate zellij  zellij setup --generate-completion zsh
generate gh      gh completion -s zsh
generate codex   codex completion zsh
generate bun     bun completions
generate rg      rg --generate complete-zsh
generate docker  docker completion zsh
generate kubectl kubectl completion zsh
generate helm    helm completion zsh
generate rustup  rustup completions zsh
if command -v rustup >/dev/null 2>&1; then
  # cargo's completion is shipped via rustup, not cargo itself.
  generate cargo rustup completions zsh cargo
fi

# ── ~/.zshrc wiring ──────────────────────────────────────────────────────────
if [[ ! -f "$ZSHRC" ]]; then
  echo "  no $ZSHRC — skipping shell wiring (drop the snippet manually)"
  exit 0
fi

# Build the block. Single-quoted heredoc keeps $fpath literal; we splice
# COMP_DIR via a separate substitution.
read -r -d '' BLOCK <<EOF || true
$MARK_BEGIN
# Managed by 0_agents/lib/install-completions.sh — re-run that script to refresh.
fpath=("$COMP_DIR" \$fpath)
$MARK_END
EOF

# Strip any existing managed block (line-exact marker match).
strip_block() {
  local file="$1"
  local tmp; tmp="$(mktemp)"
  local in_block=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$MARK_BEGIN" ]]; then in_block=1; continue; fi
    if [[ "$in_block" -eq 1 ]]; then
      if [[ "$line" == "$MARK_END" ]]; then in_block=0; fi
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
}

had_block=0
if grep -qxF "$MARK_BEGIN" "$ZSHRC"; then
  had_block=1
  strip_block "$ZSHRC"
fi

# Insert before the oh-my-zsh source line so its compinit picks up the fpath.
# If oh-my-zsh isn't used, append at end and run our own compinit.
insert_before_omz() {
  local file="$1"
  local tmp; tmp="$(mktemp)"
  local inserted=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$inserted" -eq 0 && "$line" == 'source $ZSH/oh-my-zsh.sh' ]]; then
      printf '%s\n\n' "$BLOCK" >> "$tmp"
      inserted=1
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
  return $((1 - inserted))
}

if insert_before_omz "$ZSHRC"; then
  if [[ "$had_block" -eq 1 ]]; then
    echo "✓ refreshed completions block (before oh-my-zsh source) in $ZSHRC"
  else
    echo "✓ inserted completions block (before oh-my-zsh source) in $ZSHRC"
  fi
else
  # No oh-my-zsh source line — append at end with our own compinit.
  {
    printf '\n%s\n' "$MARK_BEGIN"
    printf '# Managed by 0_agents/lib/install-completions.sh — re-run that script to refresh.\n'
    printf 'fpath=("%s" $fpath)\n' "$COMP_DIR"
    printf 'autoload -Uz compinit && compinit -u\n'
    printf '%s\n' "$MARK_END"
  } >> "$ZSHRC"
  if [[ "$had_block" -eq 1 ]]; then
    echo "✓ refreshed completions block (appended; no oh-my-zsh detected) in $ZSHRC"
  else
    echo "✓ appended completions block (no oh-my-zsh detected) in $ZSHRC"
  fi
fi

echo ""
echo "Done. Reload your shell:  exec zsh"
echo "Then test:                zellij <Tab>   gh <Tab>   codex <Tab>"
