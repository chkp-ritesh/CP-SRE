FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
  iperf3 \
  ipset \
  iptables \
  curl \
  jq \
  iputils-ping \
  && apt-get clean

COPY entrypoint.sh /entrypoint.sh
COPY ../scripts/*.sh /usr/local/bin/
COPY prometheus.yml /etc/prometheus/prometheus.yml

ENTRYPOINT ["/entrypoint.sh"]
