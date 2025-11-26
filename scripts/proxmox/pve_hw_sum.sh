#!/usr/bin/env bash
# Collect basic Proxmox node hardware info through the API
# Requires: curl, jq
# Usage: ./pve_hardware_summary.sh <PVE_HOST> <USER@REALM> <API_TOKEN_ID> <API_SECRET>

set -euo pipefail
IFS=$'\n\t'

PVE_HOST="${1:-}"
PVE_USER="${2:-}"
PVE_TOKEN_ID="${3:-}"
PVE_TOKEN_SECRET="${4:-}"
PVE_PORT="${5:-}"

if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$PVE_TOKEN_ID" || -z "$PVE_TOKEN_SECRET" ]]; then
  echo "Usage: $0 <pve_host> <user@realm> <token_id> <token_secret>"
  exit 1
fi

AUTH_HEADER="Authorization: PVEAPIToken=${PVE_USER}!${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}"

# === Fetch node list ===
echo "[INFO] Fetching node list..."
NODES=$(curl -s -k -H "$AUTH_HEADER" "https://${PVE_HOST}:${PVE_PORT}/api2/json/nodes" \
  | jq -r '.data[].node')

for NODE in $NODES; do
  echo "=============================="
  echo "Node: $NODE"
  echo "=============================="

  # --- CPU & memory ---
  STATUS=$(curl -s -k -H "$AUTH_HEADER" "https://${PVE_HOST}:${PVE_PORT}/api2/json/nodes/${NODE}/status" | jq -r '.data')
  CPU_MODEL=$(echo "$STATUS" | jq -r '.cpuinfo.model')
  CPU_CORES=$(echo "$STATUS" | jq -r '.cpuinfo.cpus')
  MEM_TOTAL=$(echo "$STATUS" | jq -r '.memtotal')
  MEM_USED=$(echo "$STATUS" | jq -r '.memused')

  echo "CPU Model     : $CPU_MODEL"
  echo "CPU Cores     : $CPU_CORES"
  echo "Memory (used) : $(numfmt --to=iec $MEM_USED)/$(numfmt --to=iec $MEM_TOTAL)"

  # --- Disks ---
  echo "--- Disks ---"
  curl -s -k -H "$AUTH_HEADER" "https://${PVE_HOST}:${PVE_PORT}/api2/json/nodes/${NODE}/disks/list" \
    | jq -r '.data[] | "\(.devpath)  \(.model)  \(.size)"'

  # --- Storage definitions (LUN/SAN) ---
  echo "--- Storage ---"
  curl -s -k -H "$AUTH_HEADER" "https://${PVE_HOST}:${PVE_PORT}/api2/json/nodes/${NODE}/storage" \
    | jq -r '.data[] | "\(.storage)\t\(.type)\t\(.shared)\t\(.content)"'

  # --- Optional: Hardware model from dmidecode (requires SSH) ---
  if command -v ssh &>/dev/null; then
    echo "--- Host Hardware Model ---"
    ssh -o BatchMode=yes -o ConnectTimeout=3 root@"$NODE" 'dmidecode -s system-product-name 2>/dev/null || echo "N/A"' || true
  fi

  echo
done
