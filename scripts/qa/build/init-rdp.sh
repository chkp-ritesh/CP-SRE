#!/bin/bash
set -e

# Install xrdp and a lightweight desktop environment
apt-get update
apt-get install -y xrdp xfce4 xfce4-goodies

# Set xfce as the default session for xrdp
echo xfce4-session > /home/ubuntu/.xsession
chown ubuntu:ubuntu /home/ubuntu/.xsession

# Allow xrdp through firewall (not strictly needed on cloud VMs)

# Enable and start the RDP service
systemctl enable xrdp
systemctl restart xrdp
