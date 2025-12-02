#!/bin/bash

SERVER="$1"
DEST_LABEL="$3"
SOURCE_LABEL="${2:-$(hostname)}"  # Use $3 if given, otherwise fallback to hostname
DELAY="$4"

if [[ -n "$DELAY" ]]; then
  sleep "$DELAY"
fi

TIME_LIMIT=30
IPERF_PORT=5201

run_udp() {
  OUTPUT=$(timeout "$TIME_LIMIT" iperf3 -c "$SERVER" -p "$IPERF_PORT" -u -b 0 -Z -t 10 -J 2>/dev/null)

  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp value=0"
    echo "iperf3_jitter_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp value=0"
  else
    BITS=$(echo "$OUTPUT" | jq '.end.sum_received.bits_per_second // .end.sum.bits_per_second // 0')
    JITTER=$(echo "$OUTPUT" | jq '.end.sum.jitter_ms // 0')
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp value=$BITS"
    echo "iperf3_jitter_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp value=$JITTER"
  fi

  # ICMP latency (ping)
  LATENCY=$(ping -c 1 -W 1 "$SERVER" | grep 'time=' | sed -n 's/.*time=\(.*\) ms/\1/p')
  LATENCY=${LATENCY:-0}
  echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=icmp value=$LATENCY"
}

run_tcp() {
  OUTPUT=$(timeout "$TIME_LIMIT" iperf3 -c "$SERVER" -p "$IPERF_PORT" -b 0 -Z -t 10 -J 2>/dev/null)

  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp value=0"
    echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp value=0"
  else
    BITS=$(echo "$OUTPUT" | jq '.end.sum_received.bits_per_second // .end.sum.bits_per_second // 0')
    START_TIME=$(echo "$OUTPUT" | jq '.start.timestamp.timesecs')
    CONNECT_TIME=$(echo "$OUTPUT" | jq '.start.connected[0].connect_ts // .start.connected[0].connecting_to.connect_ts // 0')
    LATENCY=$(echo "$CONNECT_TIME $START_TIME" | awk '{printf "%.3f", ($1 - $2) * 1000}')
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp value=$BITS"
    echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp value=$LATENCY"
  fi
}

# Run both tests
run_udp
sleep 30
run_tcp
