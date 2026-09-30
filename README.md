# `bootstrap`

One command that turns a freshly installed Ubuntu into jo's working machine.
It fetches the GitHub SSH key from Bitwarden, clones the private
[`ansible-machines`](https://github.com/johsacher/ansible-machines) repo, and
runs its playbook.

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

You don't need this script again on that machine. Use the repo directly:

```sh
~/ansible-machines/bin/setup                 # re-apply everything
~/ansible-machines/bin/setup --check --diff  # preview only, changes nothing
~/ansible-machines/bin/setup --tags emacs    # one role only
```

Running the bootstrap again is also safe. It updates the existing checkout
instead of cloning a new one.

## One-time prerequisite (already done, not per machine)

Bitwarden must hold an item of type **SSH key** named `GitHub SSH key`,
containing a key that is registered on GitHub. The script loads it into a
temporary ssh-agent. The key is never written to disk, and it is gone when the
script exits.

The account is on the EU server (`vault.bitwarden.eu`). To use another item
name or server, edit `BW_SSH_ITEM` or `BW_SERVER`
at the top of `bootstrap.sh`.

## Dry run

To see what it would change without changing anything:

```sh
wget -O- https://raw.githubusercontent.com/johsacher/bootstrap/main/bootstrap.sh | bash -s -- --check --diff
```

Any options after `--` are passed to `ansible-playbook`.

## What it does, step by step

1. Checks that you're on Ubuntu and not running it as root.
2. Asks for the sudo password once and checks it. The password is reused for
   apt and for Ansible.
3. Installs the Bitwarden CLI (via snap). The first time it logs in to
   Bitwarden; on later runs it only unlocks, asking for the master password
   but no 2FA code.
4. Loads the SSH key into a temporary agent, and pins GitHub's host key so the
   first clone doesn't stop to ask.
5. Installs `git` and `ansible`, then clones `ansible-machines`, or updates it
   if it's already there.
6. Hands over to `ansible-machines/bin/setup`, which runs the playbook.
7. On exit, whether it succeeded or failed: locks Bitwarden again and stops
   the agent. The machine stays logged in to Bitwarden, so the next run needs
   no 2FA. On a machine that isn't yours, run `bw logout` afterwards.
