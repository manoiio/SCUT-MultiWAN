#!/bin/sh
set -eu
STAGE=/tmp/scut-ipv6-test
test -s "$STAGE/client"
umask 077
sed '1s/{/{"transport_network":"tcp6",/;
 s/"listen":[[:space:]]*"[^"]*"/"listen":"192.168.1.1:1089"/;
 s/"server":[[:space:]]*"[^"]*"/"server":"[2409:8a55:727a:5740:be24:11ff:fea4:ae10]:57502"/;
 s|"local_address_file":[[:space:]]*"[^"]*"|"local_address_file":"/tmp/scut-ipv6-test/address"|' /etc/scut-bond/client.json > "$STAGE/client.json"
printf '%s\n' 2400:6000:207:3ef1:daec:5eff:fed8:6e94 > "$STAGE/address"
(trap '' HUP; export GOMEMLIMIT=24MiB GOGC=50; exec "$STAGE/client" -config "$STAGE/client.json") > "$STAGE/client.log" 2>&1 < /dev/null &
echo $! > "$STAGE/client.pid"
