#!/bin/bash

SERVER="$1"
DEST_LABEL="$3"
SOURCE_LABEL="${2:-$(hostname)}"  # Use $3 if given, otherwise fallback to hostname
DELAY="$4"

if [[ -z "$SERVER" ]]; then
  echo "Error: Server IP required"
  exit 1
fi

if [[ -n "$DELAY" ]]; then
  sleep "$DELAY"
fi

TIME_LIMIT=10
IPERF_PORT=5201

# Function to convert bps to appropriate unit
convert_bps() {
  local bps=$1
  # Debug: Log raw bps value
  echo "DEBUG: Raw bps=$bps" >&2
  # Ensure bps is a valid number, remove trailing zeros
  bps=$(printf "%.10f" "$bps" | sed 's/0*$//;s/\.$//')
  if (( $(echo "$bps >= 1000000000" | bc -l) )); then
    printf "%.3f Gbps\n" "$(echo "$bps / 1000000000" | bc -l)"
  elif (( $(echo "$bps >= 1000000" | bc -l) )); then
    printf "%.3f Mbps\n" "$(echo "$bps / 1000000" | bc -l)"
  elif (( $(echo "$bps >= 1000" | bc -l) )); then
    printf "%.3f kbps\n" "$(echo "$bps / 1000" | bc -l)"
  else
    printf "%.0f bps\n" "$bps"
  fi
}

run_udp() {
  OUTPUT=$(timeout "$TIME_LIMIT" iperf3 -c "$SERVER" -p "$IPERF_PORT" -u -b 0 -t 10 --bidir -J 2>/dev/null)

  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,proto=udp,dir=forward, source=$SOURCE_LABEL,dest=$DEST_LABEL, value=0"  # ERROR: Extra comma and space before value
    # FIX: Remove comma: "iperf3_bits_per_second,proto=udp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
    echo "iperf3_bits_per_second,proto=udp,dir=reverse, source=$SOURCE_LABEL,dest=$DEST_LABEL, value=0"  # ERROR: Extra comma and space before value
    # FIX: Remove comma: "iperf3_bits_per_second,proto=udp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
    echo "iperf3_jitter_ms,proto=udp,dir=forward, source=$SOURCE_LABEL,dest=$DEST_LABEL, value=0"  # ERROR: Extra comma and space before value
    # FIX: Remove comma: "iperf3_jitter_ms,proto=udp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
    echo "iperf3_jitter_ms,proto=udp,dir=reverse, source=$SOURCE_LABEL,dest=$DEST_LABEL, value=0"  # ERROR: Extra comma and space before value
    # FIX: Remove comma: "iperf3_jitter_ms,proto=udp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
  else
    BITS=$(echo "$OUTPUT" | jq ".end.sum | select(.sender == false) | .bits_per_second // 0")  # ERROR: Only captures reverse direction, missing forward
    # FIX: Add BITS_FWD: BITS_FWD=$(echo "$OUTPUT" | jq '.end.streams[] | select(.udp.sender == true) | .udp.bits_per_second // 0')
    #       Change BITS to BITS_REV: BITS_REV=$(echo "$OUTPUT" | jq '.end.streams[] | select(.udp.sender == false) | .udp.bits_per_second // 0')
    #BITS_REV=$(echo "$OUTPUT" | jq '.end.streams[] | select(.udp.sender == false) | .udp.bits_per_second // 0')  # ERROR: Commented out, incomplete
    # FIX: Uncomment and use as BITS_REV
    JITTER_FWD=$(echo "$OUTPUT" | jq '.end.streams[] | select(.udp.sender == true) | .udp.jitter_ms // 0')
    JITTER_REV=$(echo "$OUTPUT" | jq '.end.streams[] | select(.udp.sender == false) | .udp.jitter_ms // 0')
    LOSS=$(echo "$OUTPUT" | jq ".end.sum.lost_percent // 0")  # ERROR: Inconsistent, uses .end.sum (reverse only)
    # FIX: Use .end.streams[]: LOSS=$(echo "$OUTPUT" | jq '.end.streams[] | select(.udp.sender == false) | .udp.lost_percent // 0')
    echo "iperf3_bits_per_second, proto=udp, dir=reverse, source=$SOURCE_LABEL,dest=$DEST_LABEL,  value=$(convert_bps $BITS)"  # ERROR: Extra spaces, comma before value, missing forward direction
    # FIX: Remove spaces, comma: "iperf3_bits_per_second,proto=udp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$(convert_bps $BITS_REV)"
    #      Add forward: "iperf3_bits_per_second,proto=udp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$(convert_bps $BITS_FWD)"
    #echo "iperf3 udp REVERSE value=$(convert_bps $BITS_REV)"  # ERROR: Non-InfluxDB format, commented out
    # FIX: Uncomment and format: "iperf3_bits_per_second,proto=udp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$(convert_bps $BITS_REV)"
    echo "iperf3 udp FORWARD Jitter source=$SOURCE_LABEL,dest=$DEST_LABEL , value=$JITTER_FWD ms"  # ERROR: Non-InfluxDB format, spaces, comma before value
    # FIX: "iperf3_jitter_ms,proto=udp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$JITTER_FWD"
    echo "iperf3 udp REVERSE Jitter source=$SOURCE_LABEL,dest=$DEST_LABEL , value=$JITTER_REV ms"  # ERROR: Non-InfluxDB format, spaces, comma before value
    # FIX: "iperf3_jitter_ms,proto=udp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$JITTER_REV"
    echo "IPERF3 UDP Packet loss source=$SOURCE_LABEL,dest=$DEST_LABEL, value=$LOSS %"  # ERROR: Non-InfluxDB format, spaces, inconsistent measurement name
    # FIX: "iperf3_packet_loss_percent,proto=udp,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$LOSS"
  fi

  # ICMP latency (ping)
  LATENCY=$(ping -c 1 -W 1 "$SERVER" | grep 'time=' | sed -n 's/.*time=\(.*\) ms/\1/p')
  LATENCY=${LATENCY:-0}
  echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL, proto=icmp value=$LATENCY"  # ERROR: Extra comma before proto
  # FIX: Remove comma: "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=icmp value=$LATENCY"
}

run_tcp() {
  OUTPUT=$(timeout "$TIME_LIMIT" iperf3 -c "$SERVER" -p "$IPERF_PORT" -b 0 -t 10 --bidir -J 2>/dev/null)

  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,proto=tcp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL, value=0"  # ERROR: Extra comma before value
    # FIX: Remove comma: "iperf3_bits_per_second,proto=tcp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
    echo "iperf3_bits_per_second,proto=tcp,dir=reverse, source=$SOURCE_LABEL,dest=$DEST_LABEL, value=0"  # ERROR: Extra comma and space before value
    # FIX: Remove comma, space: "iperf3_bits_per_second,proto=tcp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
    echo "iperf3_duration_seconds,proto=tcp,dir=reverse, source=$SOURCE_LABEL,dest=$DEST_LABEL,  value=0"  # ERROR: Extra comma and space before value
    # FIX: Remove comma, space: "iperf3_duration_seconds,proto=tcp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=0"
  else
    BITS_FWD=$(echo "$OUTPUT" | jq '.end.sum_received.bits_per_second // 0')
    BITS_REV=$(echo "$OUTPUT" | jq '.end.sum_sent.bits_per_second // 0')
    DURATION_REV=$(echo "$OUTPUT" | jq '.end.sum_sent.seconds // 0')
    echo "iperf3_bits_per_second,proto=tcp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL,  value=$(convert_bps $BITS_FWD)"  # ERROR: Extra comma and space before value
    # FIX: Remove comma, space: "iperf3_bits_per_second,proto=tcp,dir=forward,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$(convert_bps $BITS_FWD)"
    echo "iperf3_bits_per_second,proto=tcp,dir=reverse, source=$SOURCE_LABEL,dest=$DEST_LABEL ,value=$(convert_bps $BITS_REV)"  # ERROR: Extra comma, space before value
    # FIX: Remove comma, space: "iperf3_bits_per_second,proto=tcp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$(convert_bps $BITS_REV)"
    echo "iperf3_duration_seconds,proto=tcp,dir=reverse , source=$SOURCE_LABEL,dest=$DEST_LABEL, value=$DURATION_REV seconds"  # ERROR: Extra comma, space before value, unit in value
    # FIX: Remove comma, space, unit: "iperf3_duration_seconds,proto=tcp,dir=reverse,source=$SOURCE_LABEL,dest=$DEST_LABEL value=$DURATION_REV"
  fi
}

run_tcp
run_udp
