#!/bin/sh
set -eu
STAGE=/tmp/scut-ipv6-test
test -s "$STAGE/server"
umask 077
sed '1s/{/{"transport_network":"tcp6",/;
 s/"listen":[[:space:]]*"[^"]*"/"listen":"[::]:57502"/;
 s/"benchmark":[[:space:]]*false/"benchmark":true/;
 s/"benchmark_budget":[[:space:]]*[0-9]*/"benchmark_budget":3221225472/;
 s/"max_connections":[[:space:]]*[0-9]*/"max_connections":2/' /etc/scut-bond/server.json > "$STAGE/server.json"
chown -R scutbond:scutbond "$STAGE"
systemd-run --unit=scut-bond-ipv6-test --property=User=scutbond --property=AmbientCapabilities=CAP_NET_ADMIN --property=MemoryMax=128M --property=RuntimeMaxSec=1800 "$STAGE/server" -config "$STAGE/server.json"
