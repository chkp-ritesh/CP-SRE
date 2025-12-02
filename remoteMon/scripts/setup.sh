#!/bin/bash

#hostnamectl set-hostname speeedtest-site-saferx

wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add -
echo "deb https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/influxdb.list
sudo apt update && sudo apt install telegraf

sudo systemctl enable telegraf

#sudo rm /etc/apt/sources.list.d/influxdb.list
echo "deb https://repos.influxdata.com/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/influxdb.list
wget -qO- https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata.gpg > /dev/null
 sudo apt install telegraf

echo "Create Directory for Prometheus"

mkdir prometheus

echo "Create Directory for Grafana"

mkdir grafana


echo "Install Docker * Docker Compose"

sudo apt-get install docker --yes --force-yes

sudo apt-get install docker-compose --yes --force-yes

sudo apt install iperf3 --yes --force-yes

sudo apt-get install jq --yes --force-yes

sudo apt-get install hping3 --yes --force-yes

sudo setcap cap_net_raw+ep /usr/sbin/hping3
