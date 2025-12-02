#Part 1: Secure APT Sources (Recap)
#Update your /etc/apt/sources.list to use HTTPS:
#Those deb lines go into an APT sources list file — either by editing /etc/apt/sources.list or creating a new file in /etc/apt/sources.list.d/.

deb https://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb https://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse

# Part 2: Docker Host Security Checklist
#| Security Area        | Recommendation                         |
#| -------------------- | -------------------------------------- |
#| Docker version       | Use latest stable                      |
#| Docker daemon config | Disable legacy features                |
#| User access          | Limit who can run Docker               |
#| Kernel sysctl        | Harden against container escape        |
#| Logging & auditing   | Enable logging and audit Docker events |
#| Package updates      | Keep Docker + OS patched               |


#!/bin/bash
set -euo pipefail

echo "🛠️ Checking prerequisites..."
sudo apt-get install apt-transport-https ca-certificates curl gnupg lsb-release -y

echo "🔒 Updating APT lists securely..."
sudo apt-get update -o Acquire::https::Verify-Peer=true -o Acquire::https::Verify-Host=true
sudo apt-get upgrade -y
sudo apt-get autoremove -y
sudo apt-get autoclean

echo "🐳 Checking Docker installation..."
if ! command -v docker &>/dev/null; then
  echo "❌ Docker is not installed. Installing Docker CE..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install docker-ce docker-ce-cli containerd.io -y
fi

echo "🔒 Hardening Docker host..."

# Create or update Docker daemon config
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "icc": false,
  "userns-remap": "default",
  "no-new-privileges": true,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

echo "🔁 Restarting Docker..."
sudo systemctl daemon-reexec
sudo systemctl restart docker

echo "🔐 Kernel security sysctl settings..."
cat <<EOF | sudo tee /etc/sysctl.d/99-docker-hardening.conf
net.ipv4.conf.all.forwarding=1
kernel.dmesg_restrict=1
kernel.kptr_restrict=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
EOF
sudo sysctl --system

echo "✅ Docker and system are now securely updated and hardened."
