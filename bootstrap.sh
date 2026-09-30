#!/usr/bin/env bash
# Bootstrap jo's Ubuntu machine to the PRE-ANSIBLE STATE, then run the
# playbook. Public on purpose; it contains no secrets. On the new machine, as
# your normal user, in a terminal inside the desktop session:
#
#   wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash
#   wget -O- .../bootstrap.sh | bash -s -- --tags window_keys   # options go to ansible-playbook
#   (wget, not curl: a fresh Ubuntu desktop has wget but not always curl)
#   (or download it first, read it, then: bash bootstrap.sh)
#
# Pre-ansible state, once this has run:
#   - the machine's own SSH key, ~/.ssh/id_ed25519, added on GitHub by you
#   - git and ansible installed, ansible-machines cloned or updated
# Then it runs ansible-playbook, the same command you'd type yourself later:
#   cd ~/ansible-machines && ansible-playbook playbooks/ubuntu_jo.yml -K
#
# Asks for your sudo password, and the first time on a machine pauses once so
# you can paste the new public key into GitHub. Everything else is unattended.

# --- edit these ----------------------------------------------------------
REPO="git@github.com:johsacher/ansible-machines.git"  # private playbook repo
DEST="${ANSIBLE_MACHINES_DIR:-$HOME/ansible-machines}"
KEY="$HOME/.ssh/id_ed25519"
# -------------------------------------------------------------------------

# GitHub's published ed25519 host key, so the first connection doesn't stop to ask.
GH_HOSTKEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'

main() {
  set -euo pipefail
  say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
  die() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }
  github_ok() {
    # ssh -T always exits 1 at GitHub (no shell), so judge by the greeting.
    local out
    out="$(ssh -T -o BatchMode=yes git@github.com 2>&1 || true)"
    [[ $out == *"successfully authenticated"* ]]
  }

  [ "$EUID" -ne 0 ] || die "run as your normal user, not with sudo (~ would be root's home)"
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || die "Ubuntu only (found: ${ID:-unknown})"

  # 1. sudo password, asked once and reused for apt and Ansible's become.
  read -rsp "sudo password: " BECOME_PASS; echo
  printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v 2>/dev/null ||
    die "wrong sudo password"

  # 2. This machine's own SSH key, added on GitHub by hand, once.
  install -d -m 700 "$HOME/.ssh"
  grep -qxF "$GH_HOSTKEY" "$HOME/.ssh/known_hosts" 2>/dev/null ||
    echo "$GH_HOSTKEY" >> "$HOME/.ssh/known_hosts"
  if [ ! -f "$KEY" ]; then
    say "Generating $KEY"
    ssh-keygen -t ed25519 -N "" -q -C "$USER@$(hostname -s)" -f "$KEY"
  fi
  if github_ok; then
    say "GitHub already accepts this machine's key"
  else
    say "Add this key on GitHub (a browser opens; log in if asked)"
    printf '\n    Page:  https://github.com/settings/ssh/new\n'
    printf '    Title: %s\n' "$(hostname -s)"
    printf '    Key:   %s\n\n' "$(cat "$KEY.pub")"
    printf '    After a reinstall, delete the old key with the same title there too.\n'
    xdg-open https://github.com/settings/ssh/new >/dev/null 2>&1 || true
    until read -rp $'\n    Press Enter once the key is saved... ' && github_ok; do
      printf '    GitHub does not accept the key yet. Check it was saved, then Enter again.\n'
    done
    say "GitHub accepts the key"
  fi

  # 3. git, ansible and the repo, cloned with the machine's key.
  printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v   # refresh, the paste may have taken a while
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

  # 4. Pre-ansible state reached. From here on, only Ansible.
  say "Pre-ansible state reached. Running the playbook"
  cd "$DEST"
  ANSIBLE_BECOME_PASS="$BECOME_PASS" ansible-playbook playbooks/ubuntu_jo.yml "$@"
}

# Everything above only defines things; nothing runs until this last line, so a
# download that stopped halfway can't run half a script. </dev/tty because with
# `wget ... | bash` the keyboard input is the script itself; prompts would read the
# script's own text instead of your typing.
main "$@" </dev/tty
