# Iperf performance monitoring 
This is a new version to perform TCP & UDP based IPERF testing 
The docker-compose.yml file is the main orchestrator of the build on the CLIENT side only 
The remote iperf server is just running IPERF as a daemon 

The iperf jobs are executed by the iperf_metric.sh 
The iperf_metric.sh is a shell script that run from telegraf 

Installing Telegraf on the client 

wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add -
echo "deb https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/influxdb.list
sudo apt update
sudo apt install telegraf
sudo systemctl enable telegraf

create the telegraf.conf file in /etc/telegraf/telegraf.conf

Steps to Fix the GPG Key Error
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys D8FF8E1F7DF8B07E
lsb_release -sc
If needed, update the repository configuration in /etc/apt/sources.list or /etc/apt/sources.list.d/.

 telegraf version  Telegraf 1.34.3 (git: HEAD@983d399f)


The next goal is to fit this into the existing speedtest setup 

1. We can add tcp/udp to the container 
2. Install with the existing speedtest build , however 
3. We need to add the iperf_metric.sh script to the telegraf box 


Check SDP -
```bash
 wget https://sdp.perimeter81.com
--2025-07-28 16:33:47--  https://sdp.perimeter81.com/
Resolving sdp.perimeter81.com (sdp.perimeter81.com)... 34.192.67.103, 44.207.211.206, 54.161.8.87, ...
Connecting to sdp.perimeter81.com (sdp.perimeter81.com)|34.192.67.103|:443... connected.
```
[README.md](README.md)

```bash

Dry Run + Debug:
./network_tests.sh --tcp --ping 1.1.1.1 myhost cloudhost --dry-run --debug

Parallel (default):
./network_tests.sh 1.1.1.1 hostA hostB --tcp --udp --ping


Serial (disable parallelism):
./network_tests.sh 1.1.1.1 hostA hostB --tcp --udp --ping --serial
```
