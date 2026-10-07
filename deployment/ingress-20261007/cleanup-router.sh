#!/bin/sh
set -eu
S=/tmp/scut-ingress-stage-20261007
[ -d "$S" ] || exit 0
for entry in ct cm; do
 if [ -f "$S/$entry.pid" ]; then
  read -r p start < "$S/$entry.pid"
  if [ "$(awk '{print $22}' /proc/$p/stat 2>/dev/null)" = "$start" ] && [ "$(readlink /proc/$p/exe 2>/dev/null)" = /usr/bin/scut-bond ]; then kill "$p"; fi
 fi
done
if [ -f "$S/routes" ]; then
 while read -r table pref addr dst; do
  ip rule del pref "$pref" from "$addr/32" to "$dst/32" lookup "$table" 2>/dev/null || :
  ip route del table "$table" "$dst/32" 2>/dev/null || :
 done < "$S/routes"
fi
rm -f "$S/ct.json" "$S/cm.json" "$S/original-client.json"
