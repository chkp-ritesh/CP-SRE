#!/bin/bash

# --- Modular Network Test Script with Jitter and BDW Estimate ---

CONFIG_DEFAULTS() {
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
  NC_PORTS="443,80,22,8080,8443"
  DRY_RUN=false
  DEBUG=false
  SERIAL_MODE=false
  OUTPUT_FILE=""
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -R) REVERSE_MODE=true ;;
      --udp) RUN_UDP=true ;;
      --tcp) RUN_TCP=true ;;
      --mtr) RUN_MTR=true ;;
      --ping) RUN_PING=true ;;
      --nc) RUN_NC=true ;;
      --dry-run) DRY_RUN=true ;;
      --debug) DEBUG=true ;;
      --serial) SERIAL_MODE=true ;;
      --output-file=*) OUTPUT_FILE="${1#*=}" ;;
      --nc-ports=*) NC_PORTS="${1#*=}" ;;
      *)
        if [[ -z "$SERVER" ]]; then SERVER="$1"
        elif [[ -z "$SOURCE_LABEL" ]]; then SOURCE_LABEL="${1:-$(hostname)}"
        elif [[ -z "$DEST_LABEL" ]]; then DEST_LABEL="$1"
        elif [[ -z "$DELAY" ]]; then DELAY="${1:-0}"
        elif [[ -z "$OUTPUT_FORMAT" ]]; then OUTPUT_FORMAT="${1:-prometheus}"
        fi
      ;;
    esac
    shift
  done

  if ! $RUN_UDP && ! $RUN_TCP && ! $RUN_MTR && ! $RUN_PING && ! $RUN_NC; then
    RUN_UDP=true; RUN_TCP=true; RUN_MTR=true; RUN_PING=true; RUN_NC=true
  fi

  if [[ -z "$SERVER" || -z "$DEST_LABEL" ]]; then
    echo "Usage: $0 [-R] <server_ip> <source_label> <destination_label> [delay_seconds] [output_format] [--udp] [--tcp] [--mtr] [--ping] [--nc] [--nc-ports=ports] [--dry-run] [--debug] [--serial] [--output-file=path]"
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

run_ping_jitter() {
  local PACKETS=100
  local cmd="ping -c $PACKETS -W 1 $SERVER"
  local PING_OUTPUT=$(run_or_dry "$cmd" 2>/dev/null)

  PACKET_LOSS=$(echo "$PING_OUTPUT" | grep "packet loss" | awk '{print $6}' | tr -d '%')
  AVG_LATENCY=$(echo "$PING_OUTPUT" | egrep "round-trip|rtt" | awk -F'/' '{print $5}')
  JITTER=$(echo "$PING_OUTPUT" | egrep "round-trip|rtt" | awk -F'/' '{print $7}' | cut -d' ' -f1)

  PACKET_LOSS="${PACKET_LOSS:-100}"
  AVG_LATENCY="${AVG_LATENCY:-0}"
  JITTER="${JITTER:-0}"

  format_output "network_latency_avg_ms" "$AVG_LATENCY" "ping"
  format_output "network_jitter_mdev_ms" "$JITTER" "ping"
  format_output "network_packet_loss_percent" "$PACKET_LOSS" "ping"

  if [[ "$OUTPUT_FORMAT" == "markdown" || "$OUTPUT_FORMAT" == "json" ]]; then
    get_impact() {
      local jitter=$1 low=$2 high=$3
      if (( \$(echo "$jitter < $low" | bc -l) )); then echo "Low"
      elif (( \$(echo "$jitter < $high" | bc -l) )); then echo "Moderate"
      else echo "High"
      fi
    }

    format_output "jitter_impact_voip" "\"$(get_impact $JITTER 10 30)\"" "ping"
    format_output "jitter_impact_video" "\"$(get_impact $JITTER 20 50)\"" "ping"
    format_output "jitter_impact_gaming" "\"$(get_impact $JITTER 5 15)\"" "ping"
    format_output "jitter_impact_smb" "\"$(get_impact $JITTER 50 100)\"" "ping"
  fi
}

run_bdw_estimate() {
  local jitter_ms="${JITTER:-0}"
  local latency_ms="${AVG_LATENCY:-0}"
  local loss_percent="${PACKET_LOSS:-100}"

  if [[ ! -x /tmp/bdw.sh ]]; then
    $DEBUG && echo "[DEBUG] Downloading bdw.sh"
    curl -s -o /tmp/bdw.sh https://mrbucket-us-east-1.s3.amazonaws.com/bdw.sh
    chmod +x /tmp/bdw.sh
  fi

  local BW=1000
  local MTU=1420
  local WORST=4096

  local worst_out worst_num
  worst_out=$(/tmp/bdw.sh -b "$BW" -r "$latency_ms" -p "$loss_percent" -m "$MTU" -w "$WORST" 2>/dev/null)
  worst_num=$(echo "$worst_out" | awk '{print $4}' 2>/dev/null)
  worst_num="${worst_num:-0}"

  format_output "network_tcp_throughput_est_min_mbps" "$worst_num" "bdw"
}

run_all_tests() {
  [[ "$OUTPUT_FORMAT" == "markdown" ]] && {
    write_output "| Metric | Source | Destination | Protocol | Extra Tags | Value |"
    write_output "|--------|--------|-------------|----------|------------|-------|"
  }

  local pids=()
  $RUN_PING && {
    if $SERIAL_MODE; then
      run_ping_jitter
      run_bdw_estimate
    else
      (run_ping_jitter && run_bdw_estimate) & pids+=($!)
    fi
  }

  ! $SERIAL_MODE && for pid in "${pids[@]}"; do wait "$pid"; done
}

CONFIG_DEFAULTS
parse_args "$@"
run_all_tests
