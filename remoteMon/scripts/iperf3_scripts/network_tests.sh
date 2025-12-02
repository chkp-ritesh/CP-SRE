#!/bin/bash

# --- Modular Network Test Script ---
# Supports: Prometheus, JSON, CSV, Markdown outputs
# Usable for: Live CLI, Telegraf Exec Plugin, Scheduled tests

# --- Source External Functions if Modularized ---
# source ./lib/formatting.sh
# source ./lib/tests.sh

# --- Default Configuration ---
CONFIG_DEFAULTS() {
  AUTO_FORMAT=false
  SERVER=""
  SOURCE_LABEL=""
  DEST_LABEL=""
  DELAY=0
  REVERSE_MODE=false
  OUTPUT_FORMAT="prometheus"
  TIME_LIMIT=30
  IPERF_PORT=5201
  RUN_UDP=false
  RUN_TCP=false
  RUN_MTR=false
  RUN_PING=false
  RUN_NC=false
  RUN_HP=false        # <-- NEW
  NC_PORTS="443,80,22,8080,8443"
  DRY_RUN=false
  DEBUG=false
  SERIAL_MODE=false
  OUTPUT_FILE=""
}

# --- Parse Arguments ---
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -R) REVERSE_MODE=true ;;
      --udp) RUN_UDP=true ;;
      --tcp) RUN_TCP=true ;;
      --mtr) RUN_MTR=true ;;
      --ping) RUN_PING=true ;;
      --nc) RUN_NC=true ;;
      --hp) RUN_HP=true ;;
      --dry-run) DRY_RUN=true ;;
      --debug) DEBUG=true ;;
      --serial) SERIAL_MODE=true ;;
      --output-file=*) OUTPUT_FILE="${1#*=}" ;;
      --nc-ports=*) NC_PORTS="${1#*=}" ;;
      --auto-format) AUTO_FORMAT=true ;;
      *)
        if [[ -z "$SERVER" ]]; then SERVER="$1"
        elif [[ -z "$SOURCE_LABEL" ]]; then SOURCE_LABEL="${1:-$(hostname)}"
        elif [[ -z "$DEST_LABEL" ]]; then DEST_LABEL="$1"
        elif [[ -z "$DELAY" ]]; then DELAY="${1:-0}"
        elif [[ -z "$OUTPUT_FORMAT" ]]; then OUTPUT_FORMAT="${1:-prometheus}"
        fi
        if $AUTO_FORMAT; then
          # Detect format intelligently
          if [[ "$TERM" == "dumb" || -n "$TELEGRAF_EXEC_PLUGIN" ]]; then
            OUTPUT_FORMAT="prometheus"
          else
            OUTPUT_FORMAT="influx"
          fi
        fi
      ;;
    esac
    shift
  done

  # Default to all tests if none selected
  if ! $RUN_UDP && ! $RUN_TCP && ! $RUN_MTR && ! $RUN_PING && ! $RUN_NC && ! $RUN_HP; then
    RUN_UDP=true
    RUN_TCP=true
    RUN_MTR=true
    RUN_PING=true
    RUN_NC=true
  fi
  # Validate input
  if [[ -z "$SERVER" || -z "$DEST_LABEL" ]]; then
    echo "Usage: $0 [-R] <server_ip> <source_label> <destination_label> [delay_seconds] [output_format] [--udp] [--tcp] [--mtr] [--ping] [--nc] [--hping] [--nc-ports=ports] [--dry-run] [--debug] [--serial] [--output-file=path]"
    exit 1
  fi

  if $REVERSE_MODE; then
    TEMP_LABEL="$SOURCE_LABEL"
    SOURCE_LABEL="$DEST_LABEL"
    DEST_LABEL="$TEMP_LABEL"
    IPERF_REV_FLAG="-R"
  else
    IPERF_REV_FLAG=""
  fi

  [[ "$DELAY" -gt 0 ]] && sleep "$DELAY"
}

# --- Output Utilities ---
run_or_dry() {
  local cmd="$1"
  $DEBUG && echo "[DEBUG] Command: $cmd"
  if $DRY_RUN; then
    echo "[DRY-RUN] $cmd"
    return 0
  else
    eval "$cmd"
  fi
}

write_output() {
  local line="$1"
  echo "$line"
  [[ -n "$OUTPUT_FILE" ]] && echo "$line" >> "$OUTPUT_FILE"
}

format_output() {
  local metric="$1" value="$2" proto="$3" extra_tags="$4"
  case $OUTPUT_FORMAT in
    json)
      local extra_json=""
      [[ -n "$extra_tags" ]] && extra_json=$(echo "$extra_tags" | sed 's/,/","/g; s/=/":/g; s/^/{"/; s/$/}/')
      write_output $(jq -n --arg m "$metric" --arg v "$value" --arg p "$proto" --arg s "$SOURCE_LABEL" --arg d "$DEST_LABEL" --argjson e "${extra_json:-{}}" '[{"metric":$m,"value":$v,"protocol":$p,"source":$s,"destination":$d} + $e]')
      ;;
    csv)
      local formatted="${extra_tags//,/ }"
      formatted="${formatted//=/,}"
      write_output "$metric,$SOURCE_LABEL,$DEST_LABEL,$proto${formatted},$value"
      ;;
    markdown)
      local md="${extra_tags//,/ | }"
      md="${md//=/ | }"
      write_output "| $metric | $SOURCE_LABEL | $DEST_LABEL | $proto |${md} $value |"
      ;;
    *)
      write_output "$metric,source=$SOURCE_LABEL,dest=$DEST_LABEL,proto=$proto${extra_tags} value=$value"
      ;;
  esac
}

# --- Test Runners ---
run_iperf_test() {
  local proto="$1" opt="$2" bits_key="$3" metric_extra="$4" extra_key="$5"
  local cmd="timeout $TIME_LIMIT iperf3 -c $SERVER -p $IPERF_PORT $opt $IPERF_REV_FLAG -t 10 -J"
  OUTPUT=$(run_or_dry "$cmd" 2>/dev/null)
  if [[ $? -ne 0 || -z "$OUTPUT" ]]; then
    format_output "network_bits_per_second" 0 "$proto"
    [[ -n "$metric_extra" ]] && format_output "network_${metric_extra}" 0 "$proto"
  else
    local bits=$(echo "$OUTPUT" | jq "$bits_key // 0")
    format_output "network_bits_per_second" "$bits" "$proto"
    if [[ "$proto" == "udp" ]]; then
      local jitter=$(echo "$OUTPUT" | jq "$extra_key // 0")
      format_output "network_${metric_extra}" "$jitter" "$proto"
    elif [[ "$proto" == "tcp" ]]; then
      local start=$(echo "$OUTPUT" | jq '.start.timestamp.timesecs // 0')
      local connect=$(echo "$OUTPUT" | jq '.start.connected[0].connect_ts // .start.connected[0].connecting_to.connect_ts // 0')
      local latency=$(echo "$connect $start" | awk '{printf "%.3f", ($1 - $2) * 1000}')
      (( $(echo "$latency < 0" | bc -l) )) && latency=0
      format_output "network_${metric_extra}" "$latency" "$proto"
    fi
  fi
}

run_iperf_udp() { run_iperf_test "udp" "-u -b 0 -Z" '.end.sum_received.bits_per_second // .end.sum.bits_per_second' 'jitter_ms' '.end.sum.jitter_ms'; }
run_iperf_tcp() { run_iperf_test "tcp" "-b 0 -Z" '.end.sum_received.bits_per_second // .end.sum.bits_per_second' 'latency_ms' ''; }

run_mtr() {
  local cmd="timeout $TIME_LIMIT mtr -c 3 -b -w -z -r -J $SERVER"
  $DEBUG && echo "[DEBUG] MTR Command: $cmd"

  local json=$(run_or_dry "$cmd" 2>/dev/null)
  $DEBUG && echo "[DEBUG] MTR JSON: $json"

  if [[ -z "$json" ]]; then
    format_output "network_as_path" "\"unknown\"" "mtr"
    return
  fi

  local asn_path=()
  local latencies=()
  local hop_count=0

  while read -r asn latency; do
    # Keep as-is: numeric ASN, null, or ???
    asn="${asn:-unknown}"
    latency="${latency:-0}"
    asn_path+=("$asn")
    latencies+=("$latency")
    ((hop_count++))
  done < <(echo "$json" | jq -r '.report.hubs[] | [.ASN, .Latency] | @tsv')

  local unique_asns=$(printf "%s\n" "${asn_path[@]}" | sort | uniq | wc -l)
  local asn_path_str=$(IFS=','; echo "${asn_path[*]}")
  local asn_hash=$(echo "$asn_path_str" | sha256sum | awk '{print $1}')
  local total_latency=0

  for l in "${latencies[@]}"; do
    total_latency=$(echo "$total_latency + $l" | bc)
  done

  local avg_latency=$(echo "$total_latency / $hop_count" | bc -l | awk '{printf "%.2f", $1}')

  format_output "network_as_path" "\"$asn_path_str\"" "mtr"
  format_output "network_as_path_hash" "\"$asn_hash\"" "mtr"
  format_output "network_as_path_length" "$hop_count" "mtr"
  format_output "network_as_path_unique_asns" "$unique_asns" "mtr"
  format_output "network_as_path_avg_latency_ms" "$avg_latency" "mtr"
}




run_ping() {
  local cmd="ping -c 1 -W 1 $SERVER"
  local result=$(run_or_dry "$cmd" | grep 'time=' | sed -n 's/.*time=\(.*\) ms/\1/p')
  format_output "network_latency_ms" "${result:-0}" "icmp"
}

# Determine if port is open hping3 servces better
run_nc() {
  IFS=',' read -r -a ports <<< "$NC_PORTS"
  for port in "${ports[@]}"; do
    local cmd="timeout $TIME_LIMIT nc -z -vvv $SERVER $port"
    run_or_dry "$cmd" >/dev/null 2>&1
    local status=$?
    local connectivity=0
    [[ $status -eq 0 ]] && connectivity=1
    format_output "network_connectivity" "$connectivity" "nc" ",port=$port"
  done
}

# Run Synthetic TCP Connection to measure time to connect
run_hping3() {
  IFS=',' read -r -a ports <<< "$NC_PORTS"
  for port in "${ports[@]}"; do
    local output
    output=$(hping3 -S -p "$port" -c 1 "$SERVER" 2>/dev/null)
    local rtt
    rtt=$(echo "$output" | grep -oP 'rtt=[0-9.]+' | cut -d= -f2)

    local connectivity=0
    [[ -n "$rtt" ]] && connectivity=1

    format_output "network_connectivity" "$connectivity" "hping3" ",port=$port"
    format_output "connect_time_ms" "${rtt:-0}" "hping3" ",port=$port"
  done
}

run_ping_jitter() {
  local PACKETS=5
  local cmd="ping -c $PACKETS -W 1 $SERVER"
  local PING_OUTPUT=$(run_or_dry "$cmd" 2>/dev/null)

  local PACKET_LOSS=$(echo "$PING_OUTPUT" | grep "packet loss" | awk '{print $6}' | tr -d '%')
  local AVG_LATENCY=$(echo "$PING_OUTPUT" | egrep "round-trip|rtt" | awk -F'/' '{print $5}')
  local JITTER=$(echo "$PING_OUTPUT" | egrep "round-trip|rtt" | awk -F'/' '{print $7}' | cut -d' ' -f1)

  # Fallback to 0 if empty
  PACKET_LOSS="${PACKET_LOSS:-100}"
  AVG_LATENCY="${AVG_LATENCY:-0}"
  JITTER="${JITTER:-0}"

  format_output "network_latency_avg_ms" "$AVG_LATENCY" "ping"
  format_output "network_jitter_mdev_ms" "$JITTER" "ping"
  format_output "network_packet_loss_percent" "$PACKET_LOSS" "ping"

  # --- Optional: Jitter Impact Report (markdown or json only) ---
  if [[ "$OUTPUT_FORMAT" == "markdown" || "$OUTPUT_FORMAT" == "json" ]]; then
    get_impact() {
      local jitter=$1 low=$2 high=$3
      if (( $(echo "$jitter < $low" | bc -l) )); then
        echo "Low"
      elif (( $(echo "$jitter < $high" | bc -l) )); then
        echo "Moderate"
      else
        echo "High"
      fi
    }

    local voip=$(get_impact "$JITTER" 10 30)
    local video=$(get_impact "$JITTER" 20 50)
    local gaming=$(get_impact "$JITTER" 5 15)
    local smb=$(get_impact "$JITTER" 50 100)

    format_output "jitter_impact_voip" "\"$voip\"" "ping"
    format_output "jitter_impact_video" "\"$video\"" "ping"
    format_output "jitter_impact_gaming" "\"$gaming\"" "ping"
    format_output "jitter_impact_smb" "\"$smb\"" "ping"
  fi
}


# --- Run Tests ---
run_all_tests() {
  [[ "$OUTPUT_FORMAT" == "markdown" ]] && {
    write_output "| Metric | Source | Destination | Protocol | Extra Tags | Value |"
    write_output "|--------|--------|-------------|----------|------------|-------|"
  }

  local pids=()
  $RUN_UDP && { $SERIAL_MODE && run_iperf_udp || (run_iperf_udp & pids+=($!)); }
  $RUN_TCP && { $SERIAL_MODE && run_iperf_tcp || (run_iperf_tcp & pids+=($!)); }
  $RUN_MTR && { $SERIAL_MODE && run_mtr || (run_mtr & pids+=($!)); }
  $RUN_PING && { $SERIAL_MODE && run_ping || (run_ping & pids+=($!)); }
  $RUN_NC && { $SERIAL_MODE && run_nc || (run_nc & pids+=($!)); }
  $RUN_PING && { $SERIAL_MODE && run_ping_jitter || (run_ping_jitter & pids+=($!)); }
  $RUN_HP && { $SERIAL_MODE && run_hping3 || (run_hping3 & pids+=($!)); }

  ! $SERIAL_MODE && for pid in "${pids[@]}"; do wait "$pid"; done
}

# --- Main Execution ---
CONFIG_DEFAULTS
parse_args "$@"
run_all_tests
