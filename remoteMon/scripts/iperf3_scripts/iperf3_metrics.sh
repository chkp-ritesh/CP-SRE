#!/bin/bash

# --- Script Usage ---
# Usage: ./network_test.sh [-R] <server_ip> <source_label> <destination_label> [delay_seconds]
# Example: ./network_test.sh -R 192.168.1.1 my_laptop remote_server 5

# --- Initialize Variables ---
# Default values
SERVER=""
SOURCE_LABEL=""
DEST_LABEL=""
DELAY=0
REVERSE_MODE=false # Flag to track if -R is present

# --- Parse Command-Line Arguments ---
# Use getopts for option parsing
while getopts "R" opt; do
  case $opt in
    R)
      REVERSE_MODE=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1)) # Shift positional parameters past the options

# Assign remaining positional arguments
SERVER="$1"
SOURCE_LABEL="${2:-$(hostname)}" # Use $2 if given, otherwise fallback to hostname
DEST_LABEL="$3"
DELAY="${4:-0}" # Default delay to 0 if not provided

# --- Input Validation ---
if [[ -z "$SERVER" || -z "$DEST_LABEL" ]]; then
  echo "Usage: $0 [-R] <server_ip> <source_label> <destination_label> [delay_seconds]"
  echo "  -R: Run iperf in reverse mode (optional)."
  echo "  <server_ip>: The iperf3 server's IP address."
  echo "  <source_label>: Label for the source (defaults to hostname if not provided)."
  echo "  <destination_label>: Label for the destination."
  echo "  [delay_seconds]: Optional delay before starting tests."
  exit 1
fi

# Apply reverse mode logic for labels
if $REVERSE_MODE; then
  # Swap source and destination labels for reporting
  TEMP_LABEL="$SOURCE_LABEL"
  SOURCE_LABEL="$DEST_LABEL"
  DEST_LABEL="$TEMP_LABEL"
  IPERF_REV_FLAG="-R" # iperf3 flag for reverse mode
else
  IPERF_REV_FLAG=""
fi

# --- Global Test Settings ---
TIME_LIMIT=30
IPERF_PORT=5201 # Correctly defined as a number

# --- Delay Start (if specified) ---
if [[ "$DELAY" -gt 0 ]]; then
  echo "Delaying tests for $DELAY seconds..."
  sleep "$DELAY"
fi

# --- Helper Function to Run iperf Test ---
run_iperf_test() {
  local proto="$1"
  local iperf_cmd_options="$2"
  local output_bits_key="$3" # jq path for bits_per_second
  local metric_name_extra="$4" # Name for the additional metric (e.g., jitter_ms, latency_ms)
  local output_extra_key="$5" # jq path for the additional metric (or empty if calculated)

  # --- CRITICAL FIX HERE: Build command using an array ---
  local iperf_command=(
    iperf3
    -c "$SERVER"
    -p "$IPERF_PORT" # <-- No extra quotes needed here!
    ${iperf_cmd_options}
    ${IPERF_REV_FLAG}
    -t 10
    -J
  )

  # Execute the command, capturing stdout and redirecting stderr
  # Use "${iperf_command[@]}" to correctly expand the array into separate arguments
  OUTPUT=$(timeout "$TIME_LIMIT" "${iperf_command[@]}" 2>/dev/null)
  local status=$?

  if [[ $status -ne 0 || -z "$OUTPUT" ]]; then
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=$proto value=0"
    if [[ -n "$metric_name_extra" ]]; then
      echo "iperf3_${metric_name_extra},source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=$proto value=0"
    fi
  else
    local bits=$(echo "$OUTPUT" | jq "${output_bits_key} // 0")
    echo "iperf3_bits_per_second,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=$proto value=$bits"

    if [[ "$proto" == "udp" ]]; then
      local jitter=$(echo "$OUTPUT" | jq "$output_extra_key // 0")
      echo "iperf3_${metric_name_extra},source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=$proto value=$jitter"
    elif [[ "$proto" == "tcp" ]]; then
      local start_time=$(echo "$OUTPUT" | jq '.start.timestamp.timesecs // 0')
      local connect_time=$(echo "$OUTPUT" | jq '.start.connected[0].connect_ts // .start.connected[0].connecting_to.connect_ts // 0')
      local latency=$(echo "$connect_time $start_time" | awk '{printf "%.3f", ($1 - $2) * 1000}')
      # Ensure latency is not negative (can happen if connect_ts is missing or before start_time)
      if (( $(echo "$latency < 0" | bc -l) )); then latency=0; fi
      echo "iperf3_${metric_name_extra},source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=$proto value=$latency"
    fi
  fi
}

# --- Specific Test Functions ---

run_udp() {
  echo "Running UDP test..."
  # -u for UDP, -b 0 for bandwidth test (zero copy), -Z for zero copy
  run_iperf_test "udp" "-u -b 0 -Z" '.end.sum_received.bits_per_second // .end.sum.bits_per_second' 'jitter_ms' '.end.sum.jitter_ms'

  # ICMP latency (ping) - This is distinct and doesn't fit the iperf3 pattern
  # Ping is always from the client perspective, so labels don't flip based on iperf3's -R
  echo "Running ICMP latency test..."
  local latency_val=$(ping -c 1 -W 1 "$SERVER" | grep 'time=' | sed -n 's/.*time=\(.*\) ms/\1/p')
  latency_val=${latency_val:-0} # Default to 0 if ping fails
  echo "iperf3_latency_ms,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=icmp value=$latency_val"
}

run_tcp() {
  echo "Running TCP test..."
  # -b 0 for raw bandwidth test (zero copy), -Z for zero copy
  run_iperf_test "tcp" "-b 0 -Z" '.end.sum_received.bits_per_second // .end.sum.bits_per_second' 'latency_ms' '.end.sender_tcp_congestion' ''
}

# --- Execute Tests ---
run_udp
run_tcp

