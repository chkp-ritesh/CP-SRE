#!/bin/bash
set -e
sudo systemctl disable --now systemd-resolved

# Install dnsmasq
apt-get update
apt-get install -y dnsmasq

# Configure dnsmasq for lab.local
cat <<EOF | tee /etc/dnsmasq.d/lab.conf > /dev/null
listen-address=0.0.0.0
no-resolv
address=/lab.local/192.168.100.100
EOF

# Restart the service
systemctl restart dnsmasq
systemctl enable dnsmasq
