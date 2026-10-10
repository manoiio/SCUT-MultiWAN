#!/bin/sh
set -eu
D=/tmp/scut-lan-tests-v2
export PATH="$D/bin:$PATH"
mkdir -p "$D/cfg" "$D/run"
chmod +x "$D/controller" "$D/bin/"*
rm -f "$D/healthy" "$D/run/tunnel.ready"
reset() { : > "$D/ip.log"; : > "$D/nft.log"; }
reset
if "$D/controller" set 'wired;echo bad'; then exit 1; fi
[ ! -s "$D/ip.log" ]
echo 'PASS invalid argument cannot execute routing'
echo wired > "$D/cfg/mode"
reset; "$D/controller" refresh
! grep -q 'default via .* dev wan onlink' "$D/ip.log"
grep -q 'unreachable default' "$D/ip.log"
echo 'PASS missing wired health fails closed'
touch "$D/healthy"; reset; "$D/controller" refresh
grep -q 'default via 110.64.88.254 dev wan onlink' "$D/ip.log"
grep -q 'default via fe80::1 dev wan' "$D/ip.log"
! grep -q 'replace table 103' "$D/ip.log"
echo 'PASS wired IPv4/IPv6 route and original health table retained'
echo tunnel > "$D/cfg/mode"; reset; "$D/controller" refresh
! grep -q 'default dev scut-lan' "$D/ip.log"
echo 'PASS unavailable tunnel has no default route'
echo authenticated > "$D/run/tunnel.ready"; reset; "$D/controller" refresh
[ "$(grep -c 'default dev scut-lan' "$D/ip.log")" -eq 2 ]
grep -q 'from 172.31.255.2/32 lookup 106' "$D/ip.log"
echo 'PASS ready tunnel routes both families and isolated DNS source'
reset; "$D/controller" set wired
grep -q '^wired$' "$D/cfg/mode"
grep -q 'oifname != { "wan", "br-lan" }' "$D/run/firewall.nft"
grep -q 'redirect to :1053' "$D/run/firewall.nft"
! grep -q 'flush ruleset' "$D/run/firewall.nft"
echo 'PASS wired switch persists and restricts LAN forward/DNS'
reset; "$D/controller" set multi
grep -q '^multi$' "$D/cfg/mode"
! grep -q 'redirect to :1053' "$D/run/firewall.nft"
! grep -q 'oifname !=' "$D/run/firewall.nft"
grep -q 'pref 94 fwmark 0x5343 lookup 103' "$D/ip.log"
echo 'PASS multi restores original IPv4 distribution and marked proxy route'
exec 9>"$D/run/mode.lock"; flock -n 9
reset
if "$D/controller" set wired; then exit 1; fi
[ ! -s "$D/ip.log" ]
echo 'PASS real lock prevents concurrent mutation'
