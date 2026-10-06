# No real radios, network changes or authentication.
prime_legacy() {
  TEST_LEGACY=1; export TEST_LEGACY
  mkdir -p "$TEST_ROOT/tmp/scut-link-recover"
  now="$(awk '{print int($1)}' /proc/uptime)"
  printf '00:11:22:33:44:55/1000.0s %s %s 0\n' "$((now-61))" "$((now-61))" > "$TEST_ROOT/tmp/scut-link-recover/${1:-native}"
}
no_reassoc() { ! grep -q REASSOCIATE "$TEST_ROOT/trace" || fail "$*"; }
no_auth_scan() { ! grep -Eq 'LOGIN|LOGOUT|SCAN |wifi |ifdown |ifup ' "$TEST_ROOT/trace" || fail 'link repair touched Portal/DHCP/radio restart'; }
reset; run_rc 0 "$BIN/scut-link-recover" phy0-sta0; no_reassoc healthy; pass 'healthy HT association does not reconnect'
reset; TEST_LEGACY=1; export TEST_LEGACY
run_rc 0 "$BIN/scut-link-recover" phy0-sta0; grep -q REASSOCIATE "$TEST_ROOT/trace" || fail immediate-first-repair
pass 'confirmed mature legacy association repairs on first check'
reset; prime_legacy; run_rc 0 "$BIN/scut-link-recover" phy0-sta0
grep -q 'REASSOCIATE phy0-sta0' "$TEST_ROOT/trace" || fail 'confirmed legacy link not repaired'
no_auth_scan; pass 'confirmed Native legacy association recovers without auth or full scan'
reset; prime_legacy usb; run_rc 0 "$BIN/scut-link-recover" phy3-sta0
grep -q 'REASSOCIATE phy3-sta0' "$TEST_ROOT/trace" || fail 'USB legacy recovery missing'
! grep -q 'RATE phy3' "$TEST_ROOT/trace" || fail 'USB QCA cap'
no_auth_scan; pass 'USB recovery excludes QCA bitrate control'
reset; prime_legacy usb; TEST_NATIVE_ONLINE=0; TEST_CANDIDATE_ONLINE=1; export TEST_NATIVE_ONLINE TEST_CANDIDATE_ONLINE
run_rc 0 "$BIN/scut-link-recover" phy3-sta0
grep -q 'REASSOCIATE phy3-sta0' "$TEST_ROOT/trace" || fail 'healthy radio2 backup ignored'
pass 'USB can recover with radio2 as the remaining healthy Native uplink'
reset; prime_legacy; TEST_USB_ONLINE=0; export TEST_USB_ONLINE
run_rc 0 "$BIN/scut-link-recover" phy0-sta0; grep -q REASSOCIATE "$TEST_ROOT/trace" || fail last-uplink-repair
no_auth_scan; pass 'last healthy uplink can repair without a backup'
reset; prime_legacy; TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 0 "$BIN/scut-link-recover" phy0-sta0; grep -q REASSOCIATE "$TEST_ROOT/trace" || fail offline-repair
no_auth_scan; pass 'offline target can repair association without authentication'
reset; prime_legacy; TEST_CONNECTED=10; export TEST_CONNECTED
run_rc 0 "$BIN/scut-link-recover" phy0-sta0; no_reassoc warmup
pass 'new association receives 30 seconds before legacy recovery'
for variant in ht stale unrelated; do
 reset; prime_legacy
 case "$variant" in ht) TEST_CACHE_HT=0; export TEST_CACHE_HT;; stale) TEST_CACHE_AGE=30001; export TEST_CACHE_AGE;; unrelated) TEST_CACHE_BSSID=00:11:22:33:44:66; export TEST_CACHE_BSSID;; esac
 run_rc 0 "$BIN/scut-link-recover" phy0-sta0; no_reassoc "$variant"
 pass "missing HT, stale or unrelated AP capabilities prevent recovery: $variant"
done
reset; prime_legacy; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 76 "$BIN/scut-link-recover" phy0-sta0; no_reassoc holiday-night
pass 'holiday night forbids legacy reassociation'
reset; prime_legacy; TEST_CLOCK='01 00 00'; export TEST_CLOCK
run_rc 76 "$BIN/scut-link-recover" phy0-sta0; no_reassoc work-night
pass 'working night forbids legacy reassociation'
reset; prime_legacy; TEST_REASSOC_FAIL=1; export TEST_REASSOC_FAIL
run_rc 1 "$BIN/scut-link-recover" phy0-sta0
run_rc 75 "$BIN/scut-link-recover" phy0-sta0
[ "$(grep -c REASSOCIATE "$TEST_ROOT/trace")" = 1 ] || fail 'uncertain request retried'
no_auth_scan; pass 'uncertain or rejected request retains one-minute retry delay'
reset; prime_legacy; TEST_REASSOC_STUCK=1; export TEST_REASSOC_STUCK
run_rc 1 "$BIN/scut-link-recover" phy0-sta0
run_rc 75 "$BIN/scut-link-recover" phy0-sta0
[ "$(grep -c REASSOCIATE "$TEST_ROOT/trace")" = 1 ] || fail 'failed restoration retried'
pass 'accepted request without HT restoration is not called successful'
reset; prime_legacy; TEST_REASSOC_IP_CHANGE=1; export TEST_REASSOC_IP_CHANGE
run_rc 1 "$BIN/scut-link-recover" phy0-sta0; no_auth_scan
grep -q '^10.1.1.10 phy0-sta0$' "$TEST_ROOT/etc/scut-multiwan/native.session" || fail 'ledger changed'
pass 'IP change defers safely without replacing the persistent session'
reset; prime_legacy; echo 'none none' > "$TEST_ROOT/etc/scut-multiwan/native.session"
run_rc 75 "$BIN/scut-link-recover" phy0-sta0; no_reassoc unbound-session
pass 'reassociation requires exact recorded session IP and device'
reset; prime_legacy
run_rc 0 sh -c '. "$1"; mw_lock native-watchdog 8 || exit; "$2" phy0-sta0' sh "$COMMON" "$BIN/scut-link-recover"
grep -q REASSOCIATE "$TEST_ROOT/trace" || fail 'caller operation lock not reused'
pass 'child recovery reuses the actual watchdog operation lock'
reset; prime_legacy
run_rc 75 sh -c '. "$1"; mw_lock qca-phy0-sta0 7 || exit; "$2" phy0-sta0; rc=$?; exit "$rc"' sh "$COMMON" "$BIN/scut-link-recover"
no_reassoc qca-busy; pass 'QCA lock contention defers reassociation'
reset; prime_legacy
run_rc 75 sh -c '. "$1"; mw_portal_lock 0 || exit; (exec 9>&-; "$2" phy0-sta0); rc=$?; exit "$rc"' sh "$COMMON" "$BIN/scut-link-recover"
no_reassoc portal-busy; pass 'another Portal transaction prevents reassociation'
reset; TEST_LEGACY=1; export TEST_LEGACY
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
grep -q 'legacy-5 6 9 12 18 24 36 48 54.*he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'legacy fallback or HE cap lost'
[ ! -f "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state" ] || fail 'legacy generated HE state'
: > "$TEST_ROOT/trace"; run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q RATE "$TEST_ROOT/trace" || fail 'incompatible mask repeated'
pass 'legacy fallback allows 54 Mbps with retained MCS7 cap and no fake HE evidence'
reset; prime_legacy; TEST_REASSOC_STUCK=1; export TEST_REASSOC_STUCK
run_rc 1 "$BIN/scut-link-recover" phy0-sta0
TEST_LEGACY=0; export TEST_LEGACY; run_rc 0 "$BIN/scut-link-recover" phy0-sta0
TEST_LEGACY=1; export TEST_LEGACY; run_rc 75 "$BIN/scut-link-recover" phy0-sta0
[ "$(grep -c REASSOCIATE "$TEST_ROOT/trace")" = 1 ] || fail 'healthy sample erased cooldown'
pass 'brief normal association cannot erase the repair cooldown'

reset; TEST_LEGACY=1; TEST_REASSOC_FAIL=1; export TEST_LEGACY TEST_REASSOC_FAIL
for desired_delay in 60 300 900 900; do
 run_rc 1 "$BIN/scut-link-recover" phy0-sta0
 read -r version attempt failures retry healthy < "$TEST_ROOT/tmp/scut-link-recover/native"
 [ "$((retry-attempt))" = "$desired_delay" ] || fail "wrong retry interval $desired_delay"
 run_rc 75 "$BIN/scut-link-recover" phy0-sta0
 printf 'v2 %s %s %s 0\n' "$((attempt-desired_delay))" "$failures" "$attempt" > "$TEST_ROOT/tmp/scut-link-recover/native"
done
[ "$failures" = 3 ] || fail 'failure counter unbounded'
no_auth_scan; pass 'failed attempts back off 60/300/900 seconds with bounded counter'
reset; TEST_LEGACY=1; TEST_USB_ONLINE=0; TEST_NATIVE_ONLINE=0; export TEST_LEGACY TEST_USB_ONLINE TEST_NATIVE_ONLINE
run_rc 0 "$BIN/scut-link-recover" phy0-sta0
grep -q REASSOCIATE "$TEST_ROOT/trace" || fail all-offline-repair
[ "$(awk '/REASSOCIATE/ {print NR;exit}' "$TEST_ROOT/trace")" = 1 ] || fail 'public probe still gates repair'
no_auth_scan; pass 'all uplinks offline does not block wireless repair or invoke authentication'
reset; prime_legacy
run_rc 75 sh -c 'exec 4>>"$1/tmp/scut-multiwan-locks/link-recover-global"; flock -n 4 || exit; "$2" phy3-sta0; rc=$?; exit "$rc"' sh "$TEST_ROOT" "$BIN/scut-link-recover"
no_reassoc global-busy; pass 'global repair lock serializes Native and USB beyond Portal lock lifetime'
reset; TEST_LEGACY=1; export TEST_LEGACY
run_rc 0 "$BIN/scut-rate-watchdog"
grep -q 'REASSOCIATE phy3-sta0' "$TEST_ROOT/trace" || fail 'USB minute repair absent'
[ "$(grep -c REASSOCIATE "$TEST_ROOT/trace")" = 2 ] || fail 'minute repair did not examine both links'
no_auth_scan; pass 'minute task repairs Native and USB sequentially without QCA tuning USB'
reset; TEST_LEGACY=1; export TEST_LEGACY
now="$(awk '{print int($1)}' /proc/uptime)"; mkdir -p "$TEST_ROOT/tmp/scut-link-recover"
printf 'old-key 0 0 %s\n' "$((now-61))" > "$TEST_ROOT/tmp/scut-link-recover/native"
run_rc 0 "$BIN/scut-link-recover" phy0-sta0
grep -q REASSOCIATE "$TEST_ROOT/trace" || fail 'legacy 30-minute state still blocks relaxed recovery'
pass 'old RAM state migrates to one-minute delay without clearing recorded attempts'
reset; TEST_LEGACY=1; export TEST_LEGACY
now="$(awk '{print int($1)}' /proc/uptime)"; mkdir -p "$TEST_ROOT/tmp/scut-link-recover"
printf 'v2 %s 2 %s 0\n' "$((now-301))" "$now" > "$TEST_ROOT/tmp/scut-link-recover/native"
run_rc 0 "$BIN/scut-link-recover" phy0-sta0
read -r version attempt failures retry healthy < "$TEST_ROOT/tmp/scut-link-recover/native"
[ "$((retry-attempt))" = 60 ] || fail 'successful recovery retained failure backoff'
printf 'v2 %s %s %s %s\n' "$attempt" "$failures" "$retry" "$((healthy-31))" > "$TEST_ROOT/tmp/scut-link-recover/native"
run_rc 0 "$BIN/scut-link-recover" phy0-sta0
read -r version attempt failures retry healthy < "$TEST_ROOT/tmp/scut-link-recover/native"
[ "$failures" = 0 ] || fail 'stable high-throughput association did not reset failures'
pass 'successful recovery returns to one-minute guard and stable HT resets failure counter'
