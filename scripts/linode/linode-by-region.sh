#!/bin/bash

OUTPUT_DIR="vm_by_region"
mkdir -p "$OUTPUT_DIR"

# 🔄 Get all available regions from Linode CLI
regions=$(linode-cli regions list --format id --text --no-headers)

for region in $regions; do
    echo "🌐 Processing region: $region"

    output_file="${OUTPUT_DIR}/${region}.txt"
    echo "Linodes in region: $region" > "$output_file"

    # 🖥️ List instance label and IPs in this region
    linode-cli linodes list \
      --region "$region" \
      --format label,ipv4 \
      --text --no-headers >> "$output_file"

    # 🧹 Format just the IPs for filtering
    formatted_ips=$(linode-cli linodes list \
      --region "$region" \
      --format ipv4 \
      --text --no-headers |
      sed 's/.*/"&"/' |
      tr '\n' '\0' |
      xargs -0 printf "%s OR " |
      sed 's/ OR $//' |
      sed 's/^/(/;s/$/)/')

    echo -e "\nFormatted IP Filter:\n$formatted_ips" >> "$output_file"

    formatted_names=$(linode-cli linodes list \
      --region "$region" \
      --format label \
      --text --no-headers |
      sed 's/.*/"&"/' |
      tr '\n' '\0' |
      xargs -0 printf "%s OR " |
      sed 's/ OR $//' |
      sed 's/^/(/;s/$/)/')

    echo -e "\nFormatted IP Filter:\n$formatted_names" >> "$output_file"

done

echo "✅ All regional outputs saved in: $OUTPUT_DIR/"
