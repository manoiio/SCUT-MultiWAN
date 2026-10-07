#!/bin/sh
set -eu
S=/tmp/scut-ingress-stage-20261007
[ ! -d "$S" ]
for t in 211 212 213; do [ -z "$(ip route show table "$t" 2>/dev/null)" ]; done
[ -z "$(ip rule show | awk '$1=="110:" || $1=="111:" || $1=="112:"')" ]
mkdir "$S"; chmod 700 "$S"; umask 077
cp /etc/scut-bond/client.json "$S/original-client.json"
slot=0
for dev in phy2-sta0 phy3-sta0 wan; do
 addr=$(ip -4 -o addr show dev "$dev" scope global | awk 'NR==1{split($4,a,"/");print a[1]}')
 gw=$(ip -4 route show dev "$dev" | awk '$1=="default"{print $3;exit}')
 [ -n "$addr" ]; [ -n "$gw" ]
 table=$((211+slot)); pref=$((110+slot))
 for dst in 119.135.0.126 120.237.234.202; do
  ip route replace table "$table" "$dst/32" via "$gw" dev "$dev" src "$addr" onlink
  ip rule add pref "$pref" from "$addr/32" to "$dst/32" lookup "$table"
  printf '%s %s %s %s\n' "$table" "$pref" "$addr" "$dst" >> "$S/routes"
 done
 slot=$((slot+1))
done
sed 's/58\.252\.223\.164:57501/119.135.0.126:57501/;s/192\.168\.1\.1:1088/192.168.1.1:1091/' "$S/original-client.json" > "$S/ct.json"
sed 's/58\.252\.223\.164:57501/120.237.234.202:57501/;s/192\.168\.1\.1:1088/192.168.1.1:1092/' "$S/original-client.json" > "$S/cm.json"
for entry in ct cm; do
 /usr/bin/scut-bond -config "$S/$entry.json" > "$S/$entry.log" 2>&1 &
 p=$!; sleep 1
 kill -0 "$p"
 printf '%s %s\n' "$p" "$(awk '{print $22}' /proc/$p/stat)" > "$S/$entry.pid"
done
