#!/bin/sh
# Remove only this IPv6 experiment. Leave deployed IPv4 proxy/campus sessions.
set -u
for pidfile in /tmp/scut-ipv6-test/client.pid /tmp/scut-ipv6-test/client-alt.pid; do
if [ -s "$pidfile" ]; then
    p=$(cat "$pidfile")
    [ "$(readlink /proc/$p/exe 2>/dev/null)" != /tmp/scut-ipv6-test/client ] || kill "$p" 2>/dev/null || :
fi
done
for name in scut_native6_test scut_usb6_test; do
    ubus call "network.interface.$name" remove '{}' >/dev/null 2>&1 || :
done
ip -6 rule del pref 86 from 2400:6000:207:3ef1:daec:5eff:fed8:6e94/128 lookup 206 2>/dev/null || :
ip -6 rule del pref 87 from 2400:6000:208:51ec:92de:80ff:fe4c:38b3/128 lookup 207 2>/dev/null || :
ip -6 route flush table 206 2>/dev/null || :
ip -6 route flush table 207 2>/dev/null || :
for pair in '206 2400:6000:207:3ef1:daec:5eff:fed8:6e94' '207 2400:6000:208:51ec:92de:80ff:fe4c:38b3' '208 2001:250:3000:3ca3:daec:5eff:fed8:6e91'; do
    set -- $pair
    current=$(ip mptcp endpoint show id "$1" 2>/dev/null | awk '{print $1}')
    [ "$current" != "$2" ] || ip mptcp endpoint delete id "$1" 2>/dev/null || :
done
