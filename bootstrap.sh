#!/usr/bin/env bash
# Bootstrap jo's Ubuntu machine. Public on purpose; it contains no secrets.
# On the new machine, as your normal user, inside the desktop session:
#
#   wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash
#   wget -O- .../bootstrap.sh | bash -s -- --check      # options go to ansible-playbook
#   (wget, not curl: a fresh Ubuntu desktop has wget but not always curl)
#   (or download it first, read it, then: bash bootstrap.sh)
#
# Asks for your sudo password, then your Bitwarden login (email, master password,
# 2FA code). Everything after that runs unattended.
#
# Only gets the private repo onto the machine, then hands over to its bin/setup.
# Everything that changes lives there, not here.

# --- edit these ----------------------------------------------------------
REPO="git@github.com:johsacher/ansible-machines.git"  # private playbook repo
DEST="${ANSIBLE_MACHINES_DIR:-$HOME/ansible-machines}"
BW_SSH_ITEM="GitHub SSH key"   # Bitwarden SSH key item that GitHub knows
BW_SERVER="https://vault.bitwarden.eu"   # EU account; empty for bitwarden.com
# -------------------------------------------------------------------------

# GitHub's published ed25519 host key, so the first clone doesn't stop to ask.
GH_HOSTKEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
AGENT_STARTED=""
BW_LOGGED_IN=""

cleanup() {
  # Runs on every exit, success or failure: close the vault and drop the key.
  # Logs out only if this script logged in; an existing login is just locked.
  if [ -n "$BW_LOGGED_IN" ]; then bw logout >/dev/null 2>&1 || true
  elif command -v bw >/dev/null; then bw lock >/dev/null 2>&1 || true; fi
  if [ -n "$AGENT_STARTED" ]; then ssh-agent -k >/dev/null 2>&1 || true; fi
}

main() {
  set -euo pipefail
  say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
  die() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

  [ "$EUID" -ne 0 ] || die "run as your normal user, not with sudo (~ would be root's home)"
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || die "Ubuntu only (found: ${ID:-unknown})"
  trap cleanup EXIT

  # 1. sudo password, asked once and reused for apt and Ansible's become.
  read -rsp "sudo password: " BECOME_PASS; echo
  printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v 2>/dev/null ||
    die "wrong sudo password"

  # 2. Bitwarden CLI and login: prompts for email, master password and 2FA code.
  command -v bw >/dev/null || { say "Installing the Bitwarden CLI"; sudo snap install bw; }
  bw_status="$(bw status | python3 -c 'import json, sys; print(json.load(sys.stdin)["status"])')"
  if [ "$bw_status" = unauthenticated ]; then
    # Only when it differs: after a logout, bw can still refuse the change
    # ("Logout required before server config update") until logged out again.
    bw_current="$(bw config server 2>/dev/null || true)"
    if [ -n "$BW_SERVER" ] && [ "${bw_current%/}" != "${BW_SERVER%/}" ]; then
      bw logout >/dev/null 2>&1 || true
      bw config server "$BW_SERVER" >/dev/null
    fi
    say "Bitwarden login"
    BW_SESSION="$(bw login --raw)"
    BW_LOGGED_IN=1
  else
    say "Bitwarden unlock"
    BW_SESSION="$(bw unlock --raw)"
  fi
  export BW_SESSION    # the playbook's community.general.bitwarden lookups use this

  # 3. SSH key: straight from the vault into a private agent, never onto disk.
  eval "$(ssh-agent -s)" >/dev/null
  AGENT_STARTED=1
  bw get item "$BW_SSH_ITEM" |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["sshKey"]["privateKey"])' |
    ssh-add - 2>/dev/null || die "could not load SSH key '$BW_SSH_ITEM' from Bitwarden"
  install -d -m 700 "$HOME/.ssh"
  grep -qxF "$GH_HOSTKEY" "$HOME/.ssh/known_hosts" 2>/dev/null ||
    echo "$GH_HOSTKEY" >> "$HOME/.ssh/known_hosts"

  # From here on, nothing needs you.
  printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v   # refresh, the login may have taken a while
  say "Installing git and ansible"
  sudo apt-get update -qq
  sudo apt-get install -y git ansible

  if [ -d "$DEST/.git" ]; then
    say "Updating $DEST"
    git -C "$DEST" pull --ff-only
  else
    say "Cloning $REPO to $DEST"
    git clone "$REPO" "$DEST"
  fi

  # Not exec: the EXIT trap has to run afterwards to close the vault and agent.
  say "Handing over to bin/setup"
  ANSIBLE_BECOME_PASS="$BECOME_PASS" "$DEST/bin/setup" "$@"
}

# Everything above only defines things; nothing runs until this last line, so a
# download that stopped halfway can't run half a script. </dev/tty because with
# `wget ... | bash` the keyboard input is the script itself; prompts would read the
# script's own text instead of your typing.
main "$@" </dev/tty
