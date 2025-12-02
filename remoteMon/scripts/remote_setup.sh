#!/bin/bash
#This Scipt set ups the iperf servers to run iperf as a service , create iptables rules to permit selective access

set -e

# Install iperf3 and ipset if not already installed
apt update
apt install -y iperf3 ipset iptables

# Create systemd service for iperf3
cat <<EOF > /etc/systemd/system/iperf3.service
[Unit]
Description=iperf3 server
After=network.target

[Service]
ExecStart=/usr/bin/iperf3 -s
Restart=on-failure
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable iperf3
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now iperf3

# Set up ipset for allowed monitor IPs
ipset create MONITORS hash:ip || true


echo "Setup complete. Add IPs to MONITORS set using:"
ipset add MONITORS 45.63.5.21
ipset add MONITORS  209.35.235.199
ipset add MONITORS  155.138.160.21
ipset add MONITORS 43.196.89.107


ipset create TRUSTED hash:ip
ipset add TRUSTED 131.226.32.118
ipset add TRUSTED 52.19.38.67
ipset add TRUSTED 54.229.211.162



iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -m set --match-set TRUSTED src -j ACCEPT
#Block DOCKER NAT traffic to ports 3000,9090
iptables -t nat -A PREROUTING -p tcp -m multiport --dports 3000,9090 -m set ! --match-set TRUSTED src -j RETURN
# Insert iptables rules
iptables -I INPUT -m set --match-set MONITORS src -p tcp --dport 5201 -j ACCEPT
iptables -I INPUT -m set --match-set MONITORS src -p udp --dport 5201 -j ACCEPT
iptables -I INPUT -m set --match-set MONITORS src -p icmp -j ACCEPT
iptables -I INPUT 5 -m set --match-set MONITORS src -p udp --match multiport --dports  9516,5201,9579 -j ACCEP
iptables -I INPUT 6 -m set --match-set MONITORS -p tcp --dport 9273 -j ACCEPT

iptables -A INPUT -i wan0 -p tcp --match multiport --dports 3000,9090,9273 -m set ! --match-set TRUSTED src -j ACCEPT
iptables -A INPUT -i wan0 -p tcp --match multiport --dports 3000,9090,9273 -m set ! --match-set MONITORS src -j ACCEPT


-A DOCKER-USER -p tcp -m multiport --dports 3000,9090 -m set --match-set TRUSTED src -j ACCEPT
-A DOCKER-USER -p tcp -m multiport --dports 3000,9090 -j REJECT --reject-with icmp-port-unreachable
-A DOCKER-USER -j RETURN
-A DOCKER-USER -p tcp -m multiport --dports 5050,5432 -m set --match-set TRUSTED src -j ACCEPT
-A DOCKER-USER -p tcp -m multiport --dports 5050,5432 -j REJECT --reject-with icmp-port-unreachable

iptables -I DOCKER-USER -p tcp -m multiport --dports 3000,9090 -m set --match-set TRUSTED src -j ACCEPT
iptables -I DOCKER-USER -p tcp -m multiport --dports 3000,9090 -j DROP

## Optionally drop non-monitored traffic (uncomment to enforce)
#iptables -A INPUT -m set --match-set MONITORS -p tcp --dport 5201 -j DROP
#iptables -A INPUT -m set --match-set MONITORS -p udp --dport 5201 -j DROP
#iptables -I INPUT -m set --match-set MONITORS src -p icmp -j ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP

sudo netfilter-persistent save
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
