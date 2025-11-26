#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

API_KEY="${API_KEY:-}"
BASE_DIR="vultr_instances"
OUT_FILE="instances.json"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: Please export API_KEY before running." >&2
  exit 1
fi

mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# === Fetch all instances with cursor pagination ===
echo "[INFO] Fetching all Vultr instances (with cursor pagination)..."
> "$OUT_FILE"

BASE_URL="https://api.vultr.com/v2/instances?per_page=500"
CURSOR=""
PAGE=1

while :; do
  URL="$BASE_URL"
  if [[ -n "$CURSOR" ]]; then
    URL="${BASE_URL}&cursor=${CURSOR}"
  fi

  echo "[DEBUG] Page $PAGE -> $URL"
  TMP=$(mktemp)
  curl -sf -H "Authorization: Bearer $API_KEY" "$URL" -o "$TMP"

  jq -c '.instances[]' "$TMP" >> "$OUT_FILE"

  NEXT=$(jq -r '.meta.links.next // empty' "$TMP")
  rm -f "$TMP"

  if [[ -z "$NEXT" || "$NEXT" == "null" || "$NEXT" == "$CURSOR" ]]; then
    echo "[INFO] No more pages after page $PAGE."
    break
  fi

  CURSOR="$NEXT"
  ((PAGE++))
done

jq -s '{instances: .}' "$OUT_FILE" > "${OUT_FILE%.json}_full.json"
mv "${OUT_FILE%.json}_full.json" "$OUT_FILE"

TOTAL=$(jq '.instances | length' "$OUT_FILE")
echo "[INFO] Done fetching. Total instances: $TOTAL"

# === Split by region and generate Markdown ===
echo "[INFO] Splitting JSON into region directories..."
jq -c '.instances[]' "$OUT_FILE" |
while IFS= read -r inst; do
  region=$(jq -r '.region' <<<"$inst")
  mkdir -p "$region"
  echo "$inst" >> "${region}/instances_tmp.json"
done

for region in */; do
  region="${region%/}"
  region_file="${region}/instances.json"
  tmp_file="${region}/instances_tmp.json"

  jq -s '{instances: .}' "$tmp_file" > "$region_file"
  rm -f "$tmp_file"

  echo "[INFO] Generating Markdown for region: $region"
  md_file="${region}/instances.md"
  region_upper=$(tr '[:lower:]' '[:upper:]' <<<"$region")

  {
    echo "# Instances in region: ${region_upper}"
    echo
    echo "| Label | IP Address | Plan | Status |"
    echo "|--------|-------------|-------|---------|"
    jq -r '.instances[] | ["\(.label)", "\(.main_ip)", "\(.plan)", "\(.status)"] | @tsv' "$region_file" |
    while IFS=$'\t' read -r label ip plan status; do
      printf "| %s | %s | %s | %s |\n" "$label" "$ip" "$plan" "$status"
    done
    echo
  } > "$md_file"
done

echo "[INFO] All regional Markdown reports generated under $BASE_DIR/"
