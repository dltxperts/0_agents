#!/usr/bin/env bash
# Create a new agent user for parallel work.
#
# This script must be run as ROOT or with sudo.
#
# Usage:
#   sudo bash create-agent-user.sh <username>
#   sudo bash create-agent-user.sh health
#   sudo bash create-agent-user.sh gearbox
#
# What it does:
#   1. Creates the user account (interactive password prompt)
#   2. Enables systemd --user linger (services persist after logout)
#   3. Prints instructions for the user to complete setup
#
# After running this script, switch to the new user and run:
#   sudo -iu <username>
#   ssh-keygen -t ed25519 -C "<username>@$(hostname)"
#   # Add the pubkey to https://github.com/settings/keys
#   git clone git@github.com:dltxperts/0_agents.git ~/Coding/0_agents
#   bash ~/Coding/0_agents/setup-server.sh

set -euo pipefail

say()   { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
err()   { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# Check if running as root
[[ "$(id -u)" -eq 0 ]] || err "Must run as root. Use: sudo bash $0 <username>"

# Require username argument
if [[ $# -eq 0 ]]; then
  err "Usage: sudo bash $0 <username>

Examples:
  sudo bash $0 health
  sudo bash $0 gearbox"
fi

USERNAME="$1"

# Validate username (only lowercase letters, numbers, underscore, hyphen)
if [[ ! "$USERNAME" =~ ^[a-z][-a-z0-9]*$ ]]; then
  err "Invalid username '$USERNAME'. Must start with lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores."
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
  err "User '$USERNAME' already exists. Use a different username or manage the existing user manually."
fi

say "Creating agent user: $USERNAME"

# Create the user (interactive password prompt)
adduser "$USERNAME"
ok "user $USERNAME created"

# Enable systemd --user linger
loginctl enable-linger "$USERNAME"
ok "systemd --user linger enabled (services will persist after logout)"

# Optional: uncomment if you want to add users to sudo group by default
# usermod -aG sudo "$USERNAME"
# ok "added to sudo group"

say "User $USERNAME created successfully!"

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Next steps — complete these AS THE NEW USER:

1. Switch to the new user:
   $ sudo -iu $USERNAME

2. Generate SSH key and add to GitHub:
   $ ssh-keygen -t ed25519 -C "$USERNAME@$(hostname)"
   $ cat ~/.ssh/id_ed25519.pub
   → Copy the output and add it at https://github.com/settings/keys

3. Clone the 0_agents repo:
   $ git clone git@github.com:dltxperts/0_agents.git ~/Coding/0_agents

4. Run the server setup:
   $ bash ~/Coding/0_agents/setup-server.sh

5. (Optional) If this user will run Cyrus:
   $ bash ~/Coding/0_agents/setup-cyrus.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The user now has:
  ✓ System account
  ✓ Systemd linger enabled (background services work)
  ✓ Ready for agent setup

EOF
