# Performance-aware health, route, rate and policy regressions (no real I/O).
reset; TEST_PRIMARY_FAIL=1; export TEST_PRIMARY_FAIL
run_rc 0 "$BIN/dualwan-refresh" force
pass 'daytime primary failure uses independent fallback HTTPS'
reset; run_rc 0 "$BIN/dualwan-refresh" force
: > "$TEST_ROOT/trace"
run_rc 0 "$BIN/dualwan-refresh" force
! grep -q 'route replace' "$TEST_ROOT/trace" || fail 'unchanged topology rewritten'
pass 'unchanged actual topology skips route writes but still probes'
reset; run_rc 0 "$BIN/dualwan-refresh" force
TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 0 "$BIN/dualwan-refresh" force
TEST_NATIVE_ONLINE=1; export TEST_NATIVE_ONLINE
: > "$TEST_ROOT/trace"; run_rc 0 "$BIN/dualwan-refresh" force
! grep -q 'default.*via 10.1.1.1' "$TEST_ROOT/trace" || fail 'single success restored removed link'
# Advance only the recovery timestamp; the actual clock stays monotonic.
now="$(awk '{print int($1)}' /proc/uptime)"
printf '0 %s recovering\n' "$((now-31))" > "$TEST_ROOT/tmp/scut-multiwan-health/wan1.route"
: > "$TEST_ROOT/trace"; run_rc 0 "$BIN/dualwan-refresh" force
grep -q 'default.*via 10.1.1.1' "$TEST_ROOT/trace" || fail 'stable recovery absent'
pass 'removed link requires two successful rounds across 30 seconds'
reset; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 0 "$BIN/dualwan-refresh" force
TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE; run_rc 0 "$BIN/dualwan-refresh" force
TEST_NATIVE_ONLINE=1; export TEST_NATIVE_ONLINE; run_rc 0 "$BIN/dualwan-refresh" force
now="$(awk '{print int($1)}' /proc/uptime)"
printf '0 %s recovering\n' "$((now-901))" > "$TEST_ROOT/tmp/scut-multiwan-health/wan1.route"
: > "$TEST_ROOT/trace"; run_rc 0 "$BIN/dualwan-refresh" force
grep -q 'default.*via 10.1.1.1' "$TEST_ROOT/trace" || fail 'night recovery reset at 15-minute interval'
pass 'holiday route recovery accepts the next 15-minute health round'
reset; TEST_RX=8; TEST_RX_VALID_LIMIT=2; export TEST_RX TEST_RX_VALID_LIMIT
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'sparse RX caused downgrade'
pass 'one valid RX sample cannot downgrade TX'
unset TEST_RX_VALID_LIMIT
reset; TEST_ASSOC_CHANGE=3; export TEST_ASSOC_CHANGE
run_rc 75 "$BIN/fix-qca-sta-rate" phy0-sta0
[ ! -f "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state" ] || fail 'changed association saved old state'
pass 'association change during sampling cancels state commit'
unset TEST_ASSOC_CHANGE
reset; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 76 "$BIN/scut-rate-watchdog"; notrace holiday-rate
pass 'holiday night has no fast rate tuning'
reset; TEST_ACTIVE=none; TEST_BEST_RC=23; export TEST_ACTIVE TEST_BEST_RC
run_rc 23 "$BIN/native-watchdog-fixture"
: > "$TEST_ROOT/trace"; run_rc 75 "$BIN/native-watchdog-fixture"
! grep -q native-best-fixture "$TEST_ROOT/trace" || fail 'failed scan bypassed backoff'
FORCE_SCAN=1; export FORCE_SCAN
run_rc 23 "$BIN/native-watchdog-fixture"
grep -q native-best-fixture "$TEST_ROOT/trace" || fail '07:00 forced check suppressed by backoff'
unset FORCE_SCAN
pass 'failed scans back off, while forced morning checks bypass backoff'
reset; run_rc 0 "$BIN/native-best" switch radio2
! grep -q 'ifdown wan2' "$TEST_ROOT/trace" || fail 'verified candidate DHCP torn down'
pass 'promotion preserves the verified candidate DHCP lease'
reset; TEST_CLEANUP_RC=1; export TEST_CLEANUP_RC
run_rc 0 "$BIN/native-best" switch radio2
pass 'cleanup command errors are accepted only after WAN down and association removal'
reset; TEST_CLEANUP_STUCK=1; export TEST_CLEANUP_STUCK
run_rc 1 "$BIN/native-best" switch radio2
pass 'stuck old WAN or association cannot report a successful Native switch'
reset; TEST_CLEANUP_UNKNOWN=1; export TEST_CLEANUP_UNKNOWN
run_rc 1 "$BIN/native-best" switch radio2
pass 'unknown teardown state cannot report a successful Native switch'
reset
run_rc 0 sh -c '. "$1"; mw_online phy0-sta0 6' sh "$COMMON"
TEST_DNS_FAIL=1; export TEST_DNS_FAIL
: > "$TEST_ROOT/trace"
run_rc 0 sh -c '. "$1"; mw_online phy0-sta0 6' sh "$COMMON"
grep -q CACHED_TLS "$TEST_ROOT/trace" || fail 'DNS failure ignored verified cache'
pass 'DNS outage can use recent verified IP while retaining TLS host validation'
now="$(awk '{print int($1)}' /proc/uptime)"
printf '%s 198.51.100.20\n' "$((now-601))" > "$TEST_ROOT/tmp/scut-multiwan-health/phy0-sta0.www.bilibili.com.dns"
: > "$TEST_ROOT/trace"
run_rc 1 sh -c '. "$1"; mw_online phy0-sta0 6' sh "$COMMON"
! grep -q CACHED_TLS "$TEST_ROOT/trace" || fail 'expired DNS cache reused'
pass 'expired CDN resolution cannot become a permanent pinned target'
reset; run_rc 0 "$BIN/dualwan-refresh" apply
: > "$TEST_ROOT/trace"; run_rc 0 "$BIN/dualwan-refresh" apply
notrace duplicate-health
pass 'overlapping periodic requests are coalesced within 20 seconds'
