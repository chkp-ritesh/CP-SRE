#!/usr/bin/env python3
import requests
import json
import os
import sys
import time
import argparse

ASN_FILTER_SET = {
    6939 , 3356, 174, 2914, 6461, 1299, 4637, # Hurricane , Lumen , Cogent , NTT , Zayo , Arelion , Telsta Common global upstreams
    21859,  # Zenlayer

    # Top Eyeball Networks for TR AS
    #9121, 34984, 15897, 16135, 20978, 47524

    # Top Eyeball Networks for CA
    #852, 577, 812, 5769, 6237, 855

    # NZ eyeball networks
    #4771, 9790, 9500, 55850, 45177, 140220,

    # Top Hong Kong Eyeball Networks
    #4760, 9269, 9232, 9304, 38819, 17924 # HKT , HK Broadband , HKBN , iCable , CMHK , China Unicom
}

CACHE_DIR = "./cache/"
os.makedirs(CACHE_DIR, exist_ok=True)

def get_cache_path(asn):
    return os.path.join(CACHE_DIR, f"asn_{asn}.json")

def fetch_asn_neighbors(asn, refresh=False):
    cache_path = get_cache_path(asn)

    if not refresh and os.path.exists(cache_path):
        with open(cache_path) as f:
            return json.load(f)

    url = "https://stat.ripe.net/data/asn-neighbours/data.json"
    params = {
        "resource": f"AS{asn}",
        "lod": 1  # Level of detail
    }

    resp = requests.get(url, params=params)
    if resp.status_code == 429:
        print(f"[WARN] Rate limited. Sleeping 10s...")
        time.sleep(10)
        resp = requests.get(url, params=params)

    resp.raise_for_status()
    data = resp.json()["data"]

    with open(cache_path, "w") as f:
        json.dump(data, f, indent=2)

    return data

def analyze_asn(asn, filter_set, refresh=False):
    data = fetch_asn_neighbors(asn, refresh=refresh)

    upstreams = set()
    downstreams = set()
    peers = set()

    for neighbor in data.get("neighbours", []):
        n_asn = neighbor.get("asn")
        n_type = neighbor.get("type")
        if n_type == "left":
            upstreams.add(n_asn)
        elif n_type == "right":
            downstreams.add(n_asn)
        else:
            peers.add(n_asn)

    return {
        "asn": asn,
        "upstreams": sorted(upstreams),
        "peers": sorted(peers),
        "downstreams": sorted(downstreams),
        "matched_upstreams": sorted(upstreams & filter_set),
        "matched_peers": sorted(peers & filter_set),
        "matched_downstreams": sorted(downstreams & filter_set),
    }

def print_result(result, fmt="json"):
    if fmt == "json":
        print(json.dumps(result, indent=2))
    else:
        print(f"[RESULT] asn={result['asn']} "
              f"matched_upstreams={','.join(map(str, result['matched_upstreams'])) or '-'} "
              f"matched_peers={','.join(map(str, result['matched_peers'])) or '-'} "
              f"matched_downstreams={','.join(map(str, result['matched_downstreams'])) or '-'}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("asn", nargs="+", help="ASN(s) to check")
    parser.add_argument("--refresh", action="store_true", help="Refresh cache")
    parser.add_argument("--format", choices=["json", "result"], default="json", help="Output format")
    args = parser.parse_args()

    for asn in args.asn:
        try:
            result = analyze_asn(int(asn), ASN_FILTER_SET, refresh=args.refresh)
            print_result(result, fmt=args.format)
        except Exception as e:
            print(f"[ERROR] Failed for ASN {asn}: {e}")

if __name__ == "__main__":
    main()
