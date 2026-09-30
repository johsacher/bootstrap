#!/usr/bin/env bash
# Bootstrap jo's Ubuntu machine to the PRE-ANSIBLE STATE. Public on purpose;
# it contains no secrets. On the new machine, as your normal user:
#
#   wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash
#   wget -O- .../bootstrap.sh | bash -s -- --tags window_keys   # options go to ansible-playbook
#   (wget, not curl: a fresh Ubuntu desktop has wget but not always curl)
#   (or download it first, read it, then: bash bootstrap.sh)
#
# Pre-ansible state, once this has run:
#   - Bitwarden CLI registered to this machine (logged in, locked)
#   - the machine's own SSH key, ~/.ssh/id_ed25519, registered on GitHub under
#     the hostname (a re-run after a reinstall replaces it, never adds one)
#   - git and ansible installed, ansible-machines cloned or updated
# Then it runs ansible-playbook, the same command you'd type yourself later:
#   cd ~/ansible-machines && ansible-playbook playbooks/ubuntu_jo.yml -K
# Run it inside the desktop session: window_keys needs the session D-Bus.
#
# Asks for your sudo password, then Bitwarden: the first time the full login
# (email, master password, 2FA code), on later runs only the master password.
# Everything after that runs unattended. The machine stays logged in to
# Bitwarden, locked. On a machine that isn't yours, run `bw logout` afterwards.

# --- edit these ----------------------------------------------------------
REPO="git@github.com:johsacher/ansible-machines.git"  # private playbook repo
DEST="${ANSIBLE_MACHINES_DIR:-$HOME/ansible-machines}"
BW_TOKEN_ITEM="GitHub token ssh-keys"   # its password: token that may manage SSH keys
BW_SERVER="https://vault.bitwarden.eu"   # EU account; empty for bitwarden.com
KEY="$HOME/.ssh/id_ed25519"
# -------------------------------------------------------------------------

# GitHub's published ed25519 host key, so the first clone doesn't stop to ask.
GH_HOSTKEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'

cleanup() {
  # Runs on every exit, success or failure. Lock, not logout: the login
  # stays, so later runs need no 2FA.
  if command -v bw >/dev/null; then bw lock >/dev/null 2>&1 || true; fi
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

  # 2. Bitwarden: log in the first time, unlock on later runs.
  command -v bw >/dev/null || { say "Installing the Bitwarden CLI"; sudo snap install bw; }
  read -r bw_status bw_url < <(bw status | python3 -c \
    'import json, sys; d = json.load(sys.stdin); print(d["status"], d.get("serverUrl") or "-")')
  if [ "$bw_status" = unauthenticated ]; then
    if [ -n "$BW_SERVER" ] && [ "${bw_url%/}" != "${BW_SERVER%/}" ]; then
      if ! bw config server "$BW_SERVER" >/dev/null 2>&1; then
        # After a `bw logout`, bw keeps the account but forgets the server,
        # then refuses the change ("Logout required before server config
        # update"). Nothing is logged in, so move that stale state aside.
        for f in "$HOME/snap/bw/current/.config/Bitwarden CLI/data.json" \
                 "$HOME/.config/Bitwarden CLI/data.json"; do
          if [ -f "$f" ]; then mv "$f" "$f.stale"; fi
        done
        bw config server "$BW_SERVER" >/dev/null
      fi
    fi
    say "Bitwarden login (first time on this machine)"
    BW_SESSION="$(bw login --raw)"
  else
    say "Bitwarden unlock"
    BW_SESSION="$(bw unlock --raw)"
  fi
  export BW_SESSION
  GITHUB_TOKEN="$(bw get password "$BW_TOKEN_ITEM")" ||
    die "no Bitwarden item '$BW_TOKEN_ITEM' with the GitHub token as its password"
  export GITHUB_TOKEN

  # 3. This machine's own SSH key, registered on GitHub under the hostname.
  install -d -m 700 "$HOME/.ssh"
  if [ ! -f "$KEY" ]; then
    say "Generating $KEY"
    ssh-keygen -t ed25519 -N "" -q -C "$USER@$(hostname -s)" -f "$KEY"
  fi
  say "Registering the key on GitHub as '$(hostname -s)'"
  KEY_TITLE="$(hostname -s)" KEY_PUB="$(cut -d' ' -f1,2 "$KEY.pub")" python3 - <<'EOF'
import json, os, urllib.error, urllib.request

title, pub = os.environ["KEY_TITLE"], os.environ["KEY_PUB"]

def api(method, path, body=None):
    req = urllib.request.Request(
        "https://api.github.com" + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + os.environ["GITHUB_TOKEN"],
                 "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"})
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"GitHub API {method} {path}: {e.code} {e.read().decode()}")

keys = api("GET", "/user/keys?per_page=100")
if any(k["key"] == pub for k in keys):
    print("already registered")
    raise SystemExit
# Only keys with THIS machine's title are replaced; all others are left alone.
for k in keys:
    if k["title"] == title:
        api("DELETE", f"/user/keys/{k['id']}")
        print(f"removed this machine's old key (id {k['id']})")
api("POST", "/user/keys", {"title": title, "key": pub})
print("registered")
EOF
  unset GITHUB_TOKEN
  grep -qxF "$GH_HOSTKEY" "$HOME/.ssh/known_hosts" 2>/dev/null ||
    echo "$GH_HOSTKEY" >> "$HOME/.ssh/known_hosts"

  # 4. git, ansible and the repo, cloned with the machine's own key.
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

  # 5. Pre-ansible state reached. From here on, only Ansible.
  say "Pre-ansible state reached. Running the playbook"
  bw lock >/dev/null 2>&1 || true   # Ansible doesn't need the vault
  cd "$DEST"
  ANSIBLE_BECOME_PASS="$BECOME_PASS" ansible-playbook playbooks/ubuntu_jo.yml "$@"
}

# Everything above only defines things; nothing runs until this last line, so a
# download that stopped halfway can't run half a script. </dev/tty because with
# `wget ... | bash` the keyboard input is the script itself; prompts would read the
# script's own text instead of your typing.
main "$@" </dev/tty
