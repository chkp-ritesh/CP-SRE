#!/bin/bash
set -e

apt-get update
apt-get install -y strongswan

cat <<EOF | tee /etc/ipsec.conf > /dev/null
config setup
         charondebug="all"
         uniqueids = yes

# Define Connections connections here
conn AUCK101
       type=tunnel
       auto=start
       keyexchange=ikev2
       authby=secret
       left=107.20.85.201
       leftid=107.20.85.201
       leftsubnet=192.168.100.0/24
       right=203.169.7.28
       rightsubnet=10.241.0.0/16
       ike=aes256-sha256-modp2048
       esp=aes256-sha256-modp2048
       aggressive=no
       keyingtries=%forever
       ikelifetime=8h
       lifetime=1h
       dpddelay=10s
       dpdtimeout=30s
       dpdaction=restart
EOF

cat <<EOF | tee /etc/ipsec.secrets > /dev/null
107.20.85.201 169.254.2.121 : PSK lrVbwmchR9HXG8uSVl2enqtLtY2RAdqC
107.20.85.201 203.169.7.28 : PSK lrVbwmchR9HXG8uSVl2enqtLtY2RAdqC
EOF

cat <<EOF | tee /etc/ipsec-tunnels.conf > /dev/null
conn AUCK101
    auto=start
    left=107.20.85.201
    leftid=107.20.85.201
    right=203.169.7.28
    rightid=203.169.7.28
    type=tunnel
    leftauth=lrVbwmchR9HXG8uSVl2enqtLtY2RAdqC
    rightauth=lrVbwmchR9HXG8uSVl2enqtLtY2RAdqC
    keyexchange=ikev2
    ike=aes256-sha256-modp2048
    esp=aes256-sha256-modp2048
    ikelifetime=8h
    lifetime=1h
    keyingtries=%forever
    leftsubnet=192.168.100.0/24
    rightsubnet=10.241.0.0/16
    dpddelay=10s
    dpdtimeout=30s
    dpdaction=restart
    mark=100
EOF

systemctl enable strongswan-starter
systemctl start strongswan-starter

cat <<EOF | tee /etc/sysctl.d/99-strongswan.conf > /dev/null
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
EOF

sysctl --system

# Add iptables rules
iptables -I INPUT 1 -p udp -m multiport --dports 500,4500 -j ACCEPT
iptables -I INPUT 2 -p tcp -m multiport --dports 8080,8443 -j ACCEPT
iptables -I INPUT 3 -p udp -m multiport --dports 53 -j ACCEPT
iptables -I INPUT 4 -p tcp -m multiport --dports 3389 -j ACCEPT

iptables -I FORWARD 1 -p tcp -m multiport --dports 8080,8443 -j ACCEPT
iptables -I FORWARD 2 -p udp -m multiport --dports 53 -j ACCEPT
iptables -I FORWARD 3 -p tcp -m multiport --dports 3389 -j ACCEPT

# Save Rules
iptables-save > /etc/iptables/rules.v4

# Begin Add VTI & Routes
ip link add AUCK101 type vti local 98.93.228.223 remote 203.169.7.28
ip addr add 169.254.2.193/30 remote 169.254.2.194/30 dev AUCK101
sysctl -w net.ipv4.conf.disable_policy=1
ip link set AUCK101 up

