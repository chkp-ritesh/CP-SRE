#!/usr/bin/env python3

import requests
import sys
import json
import os
import time

API_KEY = os.getenv("PEERINGDB_API_KEY")  # Set this in your environment securely

HEADERS = {"Authorization": f"Api-Key {API_KEY}"} if API_KEY else {}
# === CONFIGURATION ===
ASN_FILTER_SET = {
    6939, 3356, 174, 2914, 6461, # ISP ASN
    21859,  # Zenlayer included here
    # Top Eyeball Networks for TR AS
    #34984, 15897, 16135, 20978, 47524, 9121

    #Top Eyeball Networks for CA
    852, 577, 812, 5769, 6237, 855,

   #Top Eyeball Networks for NZ
    #4771, 9790, 9500, 55850, 45177, 140220

}
PEERINGDB_BASE = "https://www.peeringdb.com/api"
CACHE_DIR = "./cache"
os.makedirs(CACHE_DIR, exist_ok=True)


def get_cache_path(facility_id):
    return os.path.join(CACHE_DIR, f"facility_{facility_id}_networks.json")


def get_network_details_bulk(net_ids):
    networks = []
    for net_id in net_ids:
        url = f"{PEERINGDB_BASE}/net/{net_id}"
        for attempt in range(3):
            response = requests.get(url, headers=HEADERS)
            if response.status_code == 429:
                wait_time = 5 * (attempt + 1)
                print(f"[WARN] Rate limit hit for net_id {net_id}, retrying in {wait_time}s...")
                time.sleep(wait_time)
                continue
            response.raise_for_status()
            data = response.json().get("data", [])
            if data:
                networks.append(data[0])
            break
        else:
            print(f"[ERROR] Failed to fetch net_id {net_id} after retries.")
        time.sleep(0.2)  # still polite!
    return networks



def get_networks_at_facility(facility_id):
    """
    Fetch netfac entries for this facility and resolve full network details.
    This is the correct way to get actual peers at the facility.
    """
    url = f"{PEERINGDB_BASE}/netfac"
    response = requests.get(url, params={"facility_id": facility_id})
    response.raise_for_status()
    netfac_records = response.json().get("data", [])

    network_ids = list({record["net_id"] for record in netfac_records})
    print(f"[INFO] Found {len(network_ids)} network IDs peering at facility {facility_id}")
    return get_network_details_bulk(network_ids)


def load_or_fetch_networks(facility_id, refresh=False):
    cache_path = get_cache_path(facility_id)

    if not refresh and os.path.exists(cache_path):
        print(f"[INFO] Loading cached data from {cache_path}")
        with open(cache_path, "r") as f:
            return json.load(f)

    print(f"[INFO] Fetching data from PeeringDB for facility {facility_id}")
    networks = get_networks_at_facility(facility_id)

    with open(cache_path, "w") as f:
        json.dump(networks, f, indent=2)
    print(f"[INFO] Cached network data to {cache_path}")

    return networks


def filter_networks_by_asn(networks, asn_set):
    return [net for net in networks if net.get("asn") in asn_set]


def print_network_summary(networks):
    if not networks:
        print("[INFO] No matching networks found.")
        return
    print(f"[INFO] Found {len(networks)} matching networks:\n")
    for net in networks:
        print(f" - ASN: {net['asn']:6} | Name: {net['name']:<30} | Website: {net.get('website', 'N/A')}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 peeringdb_facility_asn_check.py <facility_id> [--refresh]")
        sys.exit(1)

    facility_id = sys.argv[1]
    refresh_flag = "--refresh" in sys.argv[2:]

    try:
        all_networks = load_or_fetch_networks(facility_id, refresh=refresh_flag)
        matching_networks = filter_networks_by_asn(all_networks, ASN_FILTER_SET)
        print_network_summary(matching_networks)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
