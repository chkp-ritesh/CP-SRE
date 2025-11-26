#!/bin/bash
# Script gets latest version

REPOS="git@github.com:perimeter-81/sx-core-redis.git git@github.com:perimeter-81/saferx-guard-core.git git@github.com:perimeter-81/sx-core-guacd.git git@github.com:safervpn/saferwatcher.git git@github.com:perimeter-81/p81zero-server.git git@github.com:perimeter-81/sx-core-wireguard.git git@github.com:perimeter-81/sx-core-wireguard.git git@github.com:perimeter-81/sx-core-strongswan.git git@github.com:perimeter-81/sx-core-openvpn.git git@github.com:perimeter-81/saferx-resolver.git git@github.com:perimeter-81/sx-core-ntc.git git@github.com:perimeter-81/sx-core-connectivity.git git@github.com:perimeter-81/sx-url-filtering-feed.git git@github.com:perimeter-81/sx-core-vector.git"

for i in $REPOS; do
  TAG=`git ls-remote --refs --tags --sort=v:refname $i | tail -n 1 | grep -Eo 'v\d+.\d+.\d+'`
  echo $i $TAG
done

~
