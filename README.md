# `bootstrap`

One command that turns a freshly installed Ubuntu into jo's working machine.
It brings the machine to the **pre-ansible state** (Bitwarden registered,
the machine's own GitHub key, the private
[`ansible-machines`](https://github.com/johsacher/ansible-machines) repo
cloned), then runs its playbook.

This script is public on purpose and contains no secrets. Everything private
stays in Bitwarden and in the private repo.

## Simple instruction
just run:

```sh
wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash
```

- starts with minimal interaction:
  - asking **sudo password**
  - asking **Bitwarden login**: email, master password, 2FA code (first time;
    later runs only the master password)
- after that: GRAB A COFFEE AND COME BACK!

The repo ends up in `~/ansible-machines`.

## Later runs

You don't need this script again on that machine. Use Ansible directly:

```sh
cd ~/ansible-machines
ansible-playbook playbooks/ubuntu_jo.yml -K                  # re-apply everything
ansible-playbook playbooks/ubuntu_jo.yml -K --check --diff   # preview only
ansible-playbook playbooks/ubuntu_jo.yml -K --tags emacs     # one role only
```

`-K` asks for the sudo password. No Bitwarden needed.

Running the bootstrap again is also safe. It updates the existing checkout
instead of cloning a new one.

## One-time prerequisite (already done, not per machine)

Bitwarden must hold a **Login** item named `GitHub token ssh-keys`, whose
password is a GitHub fine-grained token with only **Account permissions →
Git SSH keys: Read and write**. The script uses it to register the machine's
own key, and nothing else.

The account is on the EU server (`vault.bitwarden.eu`). To use another item
name or server, edit `BW_TOKEN_ITEM` or `BW_SERVER` at the top of
`bootstrap.sh`.

## Dry run

To see what it would change without changing anything:

```sh
wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash -s -- --check --diff
```

Any options after `--` are passed to `ansible-playbook`. The pre-ansible
steps (Bitwarden, the key, the clone) still happen for real; only the playbook
is a dry run.

## What it does, step by step

1. Checks that you're on Ubuntu and not running it as root.
2. Asks for the sudo password once and checks it. The password is reused for
   apt and for Ansible.
3. Installs the Bitwarden CLI (via snap). The first time it logs in to
   Bitwarden; on later runs it only unlocks, asking for the master password
   but no 2FA code.
4. Generates the machine's own key `~/.ssh/id_ed25519` (once) and registers
   it on GitHub under the hostname. After a reinstall, the old key with that
   title is replaced, so GitHub keeps one key per machine. Keys with other
   titles are never touched. Pins GitHub's host key, so the first clone
   doesn't stop to ask.
5. Installs `git` and `ansible`, then clones `ansible-machines` with that key,
   or updates it if it's already there.
6. Locks Bitwarden (Ansible doesn't need it) and runs
   `ansible-playbook playbooks/ubuntu_jo.yml`, with the sudo password from
   step 2.

It locks Bitwarden on every exit, success or failure. The machine stays logged
in, so the next run needs no 2FA. On a machine that isn't yours, run
`bw logout` afterwards, and delete its key on GitHub.
