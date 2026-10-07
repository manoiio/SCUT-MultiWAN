#!/bin/sh
set -u
/etc/init.d/scut-bond disable 2>/dev/null || :
/etc/init.d/scut-bond stop 2>/dev/null || :
sleep 2
if [ -f /var/run/scut-bond/paths ]; then
    while read -r slot dev gw addr; do
        table=$((201 + slot)); pref=$((80 + slot))
        current=$(ip mptcp endpoint show id "$table" 2>/dev/null | awk '{print $1}')
        [ "$current" != "$addr" ] || ip mptcp endpoint delete id "$table" >/dev/null 2>&1
        ip rule del pref "$pref" from "$addr/32" to 58.252.223.164/32 lookup "$table" 2>/dev/null || :
        ip route del table "$table" 58.252.223.164/32 2>/dev/null || :
    done < /var/run/scut-bond/paths
fi
rm -rf /var/run/scut-bond /etc/scut-bond
rm -f /usr/bin/scut-bond /usr/bin/scut-bond-paths /etc/init.d/scut-bond
logger -t scut-bond 'proxy-only rollback complete; campus services untouched'
