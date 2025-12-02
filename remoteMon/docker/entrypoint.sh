#!/bin/bash
# Harden client & run metrics collector

chmod +x /usr/local/bin/*.sh
/usr/local/bin/harden_client.sh
exec /usr/local/bin/golden_template_iperf3_metrics.sh "$@"
