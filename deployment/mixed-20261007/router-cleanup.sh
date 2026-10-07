#!/bin/sh
set -u
STAGE=/tmp/scut-mixed-test
if [ -s "$STAGE/client.pid" ]; then
 p=$(cat "$STAGE/client.pid")
 [ "$(readlink /proc/$p/exe 2>/dev/null)" != "$STAGE/client" ] || kill "$p" 2>/dev/null || :
fi
ip mptcp endpoint delete id 206 2>/dev/null || :
ip mptcp endpoint change id 202 nofullmesh 2>/dev/null || :
ip mptcp limits set subflows 2 add_addr_accepted 0
