# `bootstrap`

One command that turns a freshly installed Ubuntu into jo's working machine.
It brings the machine to the **pre-ansible state** (the machine's own GitHub
key, the private
[`ansible-machines`](https://github.com/johsacher/ansible-machines) repo
cloned), then runs its playbook.

This script is public on purpose and contains no secrets.

## Simple instruction
just run:

```sh
wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash
```

- starts with minimal interaction:
  - asking **sudo password**
  - the first time on a machine: **paste the new public key into GitHub**
    (a browser opens at the right page; the script shows the key and waits)
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

`-K` asks for the sudo password.

Running the bootstrap again is also safe. The key already works, so it
doesn't pause, and it updates the existing checkout instead of cloning.

**Testing in a VM:** reverting to a fresh snapshot also discards the key. Take
a second snapshot after the first bootstrap and revert to that one for role
tests; then the key paste only comes back when you test the bootstrap itself.

## Dry run

To see what it would change without changing anything:

```sh
wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash -s -- --check --diff
```

Any options after `--` are passed to `ansible-playbook`. The pre-ansible
steps (the key, the clone) still happen for real; only the playbook
is a dry run.

## What it does, step by step

1. Checks that you're on Ubuntu and not running it as root.
2. Asks for the sudo password once and checks it. The password is reused for
   apt and for Ansible.
3. Pins GitHub's host key, so the first connection doesn't stop to ask, and
   generates the machine's own key `~/.ssh/id_ed25519` (once, never
   overwritten).
4. If GitHub doesn't accept that key yet: shows it, opens
   `github.com/settings/ssh/new`, and waits until `ssh -T git@github.com`
   succeeds. Title it with the hostname; after a reinstall, delete the old key
   with that title on the same page.
5. Installs `git` and `ansible`, then clones `ansible-machines` with that key,
   or updates it if it's already there.
6. Runs `ansible-playbook playbooks/ubuntu_jo.yml`, with the sudo password
   from step 2.

On a machine that isn't yours, delete its key on GitHub afterwards.
