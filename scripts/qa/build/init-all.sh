#!/bin/bash
set -e

#####################################
# INSTALL ALL PACKAGES FIRST
#####################################

# Update and install all required packages while DNS still works
apt-get update
# Pre-seed iptables-persistent to avoid interactive prompts
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get install -y dnsmasq xrdp xfce4 xfce4-goodies strongswan python3 openssl iptables-persistent

#####################################
# DNSMASQ INSTALLATION AND SETUP
#####################################

# Now disable systemd-resolved after packages are installed
systemctl disable --now systemd-resolved
# Wait for it to fully stop and release port 53
sleep 2
# Ensure it's really stopped
killall -9 systemd-resolved 2>/dev/null || true

# Remove symlink and create static resolv.conf
rm -f /etc/resolv.conf
cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Configure dnsmasq for lab.local
cat <<EOF | tee /etc/dnsmasq.d/lab.conf > /dev/null
listen-address=0.0.0.0
no-resolv
address=/lab.local/192.168.100.100
EOF

# Restart the service
systemctl restart dnsmasq
systemctl enable dnsmasq

#####################################
# RDP (XRDP) INSTALLATION AND SETUP
#####################################

# Configure xrdp (already installed above)

# Set xfce as the default session for xrdp
echo xfce4-session > /home/ubuntu/.xsession
chown ubuntu:ubuntu /home/ubuntu/.xsession

# Enable and start the RDP service
systemctl enable xrdp
systemctl restart xrdp

#####################################
# STRONGSWAN (IPSEC) INSTALLATION AND SETUP
#####################################

# Configure strongswan (already installed above)

# Get the actual public IP of this instance
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

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
       left=${PUBLIC_IP}
       leftid=${PUBLIC_IP}
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
${PUBLIC_IP} 203.169.7.28 : PSK lrVbwmchR9HXG8uSVl2enqtLtY2RAdqC
EOF

systemctl enable strongswan-starter
systemctl start strongswan-starter
# Wait for strongswan to fully start
sleep 3

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
ip link add AUCK101 type vti local ${PUBLIC_IP} remote 203.169.7.28
ip addr add 169.254.2.193/30 remote 169.254.2.194/30 dev AUCK101
sysctl -w net.ipv4.conf.disable_policy=1
ip link set AUCK101 up

#####################################
# START HTTP/HTTPS TEST SERVERS
#####################################

# Install cert tools if needed (already installed above)

# Create dummy HTML file
mkdir -p /home/ubuntu/webserver
cd /home/ubuntu/webserver
echo "<h1>QA NEW SITE HTTP PAGE</h1>" > index.html

# Create self-signed cert (valid 1 year)
openssl req -new -x509 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/CN=localhost"

# Start HTTP on 0.0.0.0:8080
nohup python3 -m http.server 8080 --bind 0.0.0.0 > http.log 2>&1 &

# Create Python HTTPS server script
cat <<'EOFPY' > https_server.py
import http.server
import ssl
import os

os.chdir('/home/ubuntu/webserver')

server_address = ('0.0.0.0', 8443)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('cert.pem', 'key.pem')

httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

print("HTTPS Server running on port 8443")
httpd.serve_forever()
EOFPY

# Start HTTPS server
nohup python3 https_server.py > https.log 2>&1 &

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/webserver

echo "All services initialized successfully!" > /var/log/init-all.log
