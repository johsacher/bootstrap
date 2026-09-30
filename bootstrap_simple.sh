#!/bin/bash
set -e
read -rsp "sudo password: " P; echo
echo "$P" | sudo -S -p '' -v
sudo snap install bw
export BW_SESSION="$(bw login --raw)"
eval "$(ssh-agent -s)"
bw get item "GitHub SSH key" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sshKey"]["privateKey"])' | ssh-add -
mkdir -p -m 700 ~/.ssh
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> ~/.ssh/known_hosts
sudo apt-get update && sudo apt-get install -y git ansible
git clone git@github.com:YOU/REPO.git ~/setup
cd ~/setup
ANSIBLE_BECOME_PASS="$P" ansible-playbook site.yml
bw logout
