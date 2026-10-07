#!/bin/sh
# Run on OpenWrt BusyBox ash only. Every ip/logger call is mocked.
set -eu
HELPER=$1
T=$(mktemp -d /tmp/scut-bond-path-tests.XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/ip" <<'MOCK'
#!/bin/sh
set -eu
D=$MOCK_BOND_CASE_DIR
printf '%s\n' "$*" >> "$D/calls"
case "$*" in
 '-4 route show table 103') cat "$D/health";;
 '-4 -o addr show dev phy2-sta0 scope global') echo '2: phy2-sta0 inet 10.195.75.125/20 scope global';;
 '-4 -o addr show dev phy3-sta0 scope global') echo '3: phy3-sta0 inet 10.195.87.110/20 scope global';;
 '-4 -o addr show dev wan scope global') echo '4: wan inet 110.64.88.149/24 scope global';;
 '-6 -o addr show dev wan scope global') cat "$D/v6addr";;
 '-6 route get '*) cat "$D/v6route"; test ! -f "$D/route-error";;
 'route show table '*) test ! -f "$D/collision" || echo 'unrelated route';;
 'rule show') :;;
 'mptcp endpoint show id '*) awk -v id="$5" '$1==id{print $2}' "$D/endpoints";;
 'mptcp endpoint add '*)
   addr=$4; shift 4; id=''
   while [ "$#" -gt 0 ]; do [ "$1" != id ] || id=$2; shift; done
   test ! -f "$D/add-error" || exit 1
   printf '%s %s\n' "$id" "$addr" >> "$D/endpoints";;
 'mptcp endpoint delete id '*) awk -v id="$5" '$1!=id' "$D/endpoints" > "$D/ep.new"; mv "$D/ep.new" "$D/endpoints";;
 'mptcp limits set '*|'route replace '*|'route del '*|'rule add '*|'rule del '*) :;;
 *) echo 'unexpected mocked ip command' >&2; exit 2;;
esac
MOCK
cat > "$T/bin/logger" <<'MOCK'
#!/bin/sh
set -eu
D=$MOCK_BOND_CASE_DIR
cat "$SCUT_BOND_STATE/local-address" > "$D/local.snapshot"
cat "$SCUT_BOND_STATE/fallback-address" > "$D/fallback.snapshot"
cat "$SCUT_BOND_STATE/mode" > "$D/mode.snapshot"
cat "$D/endpoints" > "$D/endpoints.snapshot"
MOCK
chmod 700 "$T/bin/ip" "$T/bin/logger"
for c in ipv4 mixed wired-down no-gua deprecated wrong-route unreachable collision add-failure; do
 D=$T/$c; mkdir -p "$D"; : > "$D/endpoints"; : > "$D/calls"
 printf '%s\n' 'nexthop via 10.195.79.254 dev phy2-sta0 weight 1' 'nexthop via 10.195.95.254 dev phy3-sta0 weight 1' 'nexthop via 110.64.88.254 dev wan weight 1' > "$D/health"
 echo '3: wan inet6 2001:250:3000:3ca3:daec:5eff:fed8:6e91/64 scope global dynamic' > "$D/v6addr"
 echo '2409:8a55:727a:5740:be24:11ff:fea4:ae10 from 2001:250:3000:3ca3:daec:5eff:fed8:6e91 via fe80::1 dev wan' > "$D/v6route"
 [ "$c" = ipv4 ] || touch "$D/mixed.enabled"
 case "$c" in
  wired-down) sed -i '/dev wan/d' "$D/health";;
  no-gua) : > "$D/v6addr";;
  deprecated) echo '3: wan inet6 2001:250::1/64 scope global deprecated' > "$D/v6addr";;
  wrong-route) echo 'default dev phy3-sta0' > "$D/v6route";;
  unreachable) echo 'unreachable 2409:8a55::/32 dev wan' > "$D/v6route";;
  collision) touch "$D/collision";;
  add-failure) touch "$D/add-error";;
 esac
 status=0
 PATH="$T/bin:$PATH" MOCK_BOND_CASE_DIR="$D" SCUT_BOND_STATE="$D/state" SCUT_BOND_MIXED_FILE="$D/mixed.enabled" SCUT_BOND_ONCE=1 sh "$HELPER" || status=$?
 case "$c" in
  collision)
   test "$status" -eq 1
   ! grep -Eq '^(route replace|rule add|mptcp endpoint add|mptcp limits set)' "$D/calls";;
  add-failure)
   test ! -e "$D/local.snapshot";;
  mixed)
   test "$(cat "$D/local.snapshot")" = 2001:250:3000:3ca3:daec:5eff:fed8:6e91
   test "$(cat "$D/fallback.snapshot")" = 10.195.75.125
   grep -q 'id 201 subflow fullmesh' "$D/calls"
   grep -q 'id 202 subflow fullmesh' "$D/calls"
   ! grep -q 'endpoint add .*id 203' "$D/calls"
   grep -q 'add_addr_accepted 1' "$D/calls"
   test "$(wc -l < "$D/endpoints.snapshot")" -eq 2;;
  *)
   test "$(cat "$D/local.snapshot")" = 10.195.75.125
   grep -q '^ipv4 ' "$D/mode.snapshot"
   ! grep -q 'fullmesh' "$D/calls"
   grep -q 'id 202 subflow' "$D/calls";;
 esac
 test ! -s "$D/endpoints"
 test ! -e "$D/state/local-address"
 test ! -e "$D/state/paths"
 echo "PASS $c"
done
echo '9 BOND PATH GROUPS PASSED'
