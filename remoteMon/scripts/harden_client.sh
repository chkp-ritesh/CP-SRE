ipset create TRUSTED hash:ip
ipset add TRUSTED 131.226.32.118
ipset add TRUSTED 52.19.38.67

iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -m set --match-set TRUSTED src -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 3000,9090,9579,443,80,8080,5201,9201  -m set --match-set TRUSTED src -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 3000,9090,9579,443,80,8080,5201,9201  -m set --match-set MONITORS  src -j ACCEPT
iptables -A INPUT -p icmp -m set --match-set TRUSTED src -j ACCEPT
iptables -A INPUT -p icmp -m set --match-set MONITORS src -j ACCEPT
#Specifically DROP ANY not allowed traffic to any containers
iptables -I FORWARD 1 -m set ! --match-set TRUSTED src -j DROP
iptables -I FORWARD 2 -m set ! --match-set MONITORS src -j DROP


iptables-save > /etc/iptables.rules

ipset save > /etc/ipset.conf


