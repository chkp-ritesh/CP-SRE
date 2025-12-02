#!/bin/bash

SERVER="$1"
DEST_LABEL="$3"
SOURCE_LABEL="${2:-$(hostname)}"
DELAY="$4"

if [[ -n "$DELAY" ]]; then
  sleep "$DELAY"
fi

TIME_LIMIT=10
IPERF_PORT=5201

run_udp() {
  OUTPUT=$(timeout "$TIME_LIMIT" iperf3 -c "$SERVER" -p "$IPERF_PORT" -u -b 0 -t 10 --bidir -J 2>/dev/null)

  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=forward value=0"
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=reverse value=0"
    echo "iperf3_jitter_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=forward value=0"
    echo "iperf3_jitter_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=reverse value=0"
    echo "iperf3_loss_percent,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=forward value=0"
    echo "iperf3_loss_percent,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=reverse value=0"
  else
    # Forward (client-to-server)
    BITS_FORWARD=$(echo "$OUTPUT" | jq '.end.sum_sent.bits_per_second // 0')
    JITTER_FORWARD=$(echo "$OUTPUT" | jq '.end.sum_sent.jitter_ms // 0')
    LOSS_FORWARD=$(echo "$OUTPUT" | jq '.end.sum.lost_percent // 0')
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=forward value=$BITS_FORWARD"
    echo "iperf3_jitter_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=forward value=$JITTER_FORWARD"
    echo "iperf3_loss_percent,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=forward value=$LOSS_FORWARD"

    # Reverse (server-to-client)
    BITS_REVERSE=$(echo "$OUTPUT" | jq '.end.sum_received.bits_per_second // 0')
    JITTER_REVERSE=$(echo "$OUTPUT" | jq '.end.sum_received.jitter_ms // 0')
    LOSS_REVERSE=$(echo "$OUTPUT" | jq '.end.sum_received.lost_percent // 0')
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=reverse value=$BITS_REVERSE"
    echo "iperf3_jitter_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=reverse value=$JITTER_REVERSE"
    echo "iperf3_loss_percent,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=udp,direction=reverse value=$LOSS_REVERSE"
  fi

  # ICMP latency (ping)
  LATENCY=$(ping -c 1 -W 1 "$SERVER" | grep 'time=' | sed -n 's/.*time=\(.*\) ms/\1/p')
  LATENCY=${LATENCY:-0}
  echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=icmp value=$LATENCY"
}

run_tcp() {
  OUTPUT=$(timeout "$TIME_LIMIT" iperf3 -c "$SERVER" -p "$IPERF_PORT" -b 0 -t 10 --bidir -J 2>/dev/null)

  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp,direction=forward value=0"
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp,direction=reverse value=0"
    echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp value=0"
    echo "iperf3_retransmits,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp,direction=forward value=0"
  else
    # Forward (client-to-server)
    BITS_FORWARD=$(echo "$OUTPUT" | jq '.end.sum_sent.bits_per_second // 0')
    RETRANSMITS=$(echo "$OUTPUT" | jq '.end.sum_sent.retransmits // 0')
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp,direction=forward value=$BITS_FORWARD"
    echo "iperf3_retransmits,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp,direction=forward value=$RETRANSMITS"

    # Reverse (server-to-client)
    BITS_REVERSE=$(echo "$OUTPUT" | jq '.end.sum_received.bits_per_second // 0')
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp,direction=reverse value=$BITS_REVERSE"

    # Latency (connect time)
    START_TIME=$(echo "$OUTPUT" | jq '.start.timestamp.timesecs')
    CONNECT_TIME=$(echo "$OUTPUT" | jq '.start.connected[0].connect_ts // .start.connected[0].connecting_to.connect_ts // 0')
    LATENCY=$(echo "$CONNECT_TIME $START_TIME" | awk '{printf "%.3f", ($1 - $2) * 1000}')
    echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=tcp value=$LATENCY"
  fi
}

# Run both tests
run_udp
sleep 30
run_tcp
