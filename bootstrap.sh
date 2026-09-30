#!/usr/bin/env bash
# One-shot setup for a fresh Ubuntu machine. On the new machine, as your normal user:
#   wget https://you.github.io/setup && bash setup
#   (re-running later? use "wget -O setup ..." so the old copy is replaced, not saved as setup.1)
#
# Asks for your sudo password, then your Bitwarden login (email, master password,
# 2FA code). Everything after that runs unattended.
set -euo pipefail

# --- edit these ----------------------------------------------------------
REPO="git@github.com:YOUR_USER/YOUR_SETUP_REPO.git"  # your private playbook repo
PLAYBOOK="site.yml"                                  # playbook inside that repo
CHECKOUT="$HOME/setup"                               # where the repo gets cloned
BW_SSH_ITEM="GitHub SSH key"                         # Bitwarden SSH key item GitHub knows
BW_SERVER=""   # empty for bitwarden.com; "https://vault.bitwarden.eu" for the EU server
# -------------------------------------------------------------------------

# GitHub's published ed25519 host key, so the first clone doesn't stop to ask.
GH_HOSTKEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
AGENT_STARTED=""

cleanup() {
  # Runs on every exit, success or failure: end the vault session and drop the key.
  if command -v bw >/dev/null; then bw logout >/dev/null 2>&1 || true; fi
  if [ -n "$AGENT_STARTED" ]; then ssh-agent -k >/dev/null 2>&1 || true; fi
}

main() {
  if [ "$EUID" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo (~ would be root's home)." >&2
    exit 1
  fi
  trap cleanup EXIT

  # 1. sudo password, asked once and reused for apt and Ansible's become.
  read -rsp "sudo password: " BECOME_PASS; echo
  printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v    # a wrong password fails now, not later

  # 2. Bitwarden CLI and login: prompts for email, master password and 2FA code.
  command -v bw >/dev/null || sudo snap install bw
  if [ -n "$BW_SERVER" ]; then bw config server "$BW_SERVER" >/dev/null; fi
  BW_SESSION="$(bw login --raw)"
  export BW_SESSION    # the playbook's community.general.bitwarden lookups use this

  # 3. SSH key: straight from the vault into a private agent, never onto disk.
  command -v ssh-agent >/dev/null || sudo apt-get install -y openssh-client
  eval "$(ssh-agent -s)" >/dev/null
  AGENT_STARTED=1
  bw get item "$BW_SSH_ITEM" |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["sshKey"]["privateKey"])' |
    ssh-add -
  install -d -m 700 "$HOME/.ssh"
  grep -qxF "$GH_HOSTKEY" "$HOME/.ssh/known_hosts" 2>/dev/null ||
    echo "$GH_HOSTKEY" >> "$HOME/.ssh/known_hosts"

  # From here on, nothing needs you.
  printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v    # refresh sudo in case the login took a while
  sudo apt-get update
  sudo apt-get install -y git ansible
  [ -d "$CHECKOUT" ] || git clone "$REPO" "$CHECKOUT"
  cd "$CHECKOUT"
  if [ -f requirements.yml ]; then ansible-galaxy collection install -r requirements.yml; fi
  ANSIBLE_BECOME_PASS="$BECOME_PASS" ansible-playbook "$PLAYBOOK"
}

# Everything above only defines things; nothing runs until this last line,
# so a download that stopped halfway can't run half a script.
main "$@"
