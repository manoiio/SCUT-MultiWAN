# 2026-10-07: candidate transient deferrals, old-path release and stale DHCP.
reset; TEST_RATE_DEFER_ONCE=1; export TEST_RATE_DEFER_ONCE
run_rc 0 "$BIN/native-best" switch radio2
grep -q 'rate maintenance deferred' "$TEST_ROOT/last-output" || fail 'candidate deferral not distinguished'
grep -q '^LOGIN phy2-sta0' "$TEST_ROOT/trace" || fail 'transient rate deferral discarded candidate'
pass 'candidate retries transient QCA deferral before safe switch'
reset; TEST_RATE_FAIL=75; export TEST_RATE_FAIL
run_rc 1 "$BIN/native-best" switch radio2
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'rate deferral exhaustion authenticated'
pass 'persistent candidate rate deferral bounded and cannot authenticate'
reset; TEST_LOGOUT_DEVICE_FAIL=phy0-sta0; export TEST_LOGOUT_DEVICE_FAIL
run_rc 0 "$BIN/native-best" switch radio2
grep -q '^LOGOUT phy3-sta0 167837962' "$TEST_ROOT/trace" || fail 'fallback not exact recorded old IP'
grep -q '^LOGIN phy2-sta0' "$TEST_ROOT/trace" || fail 'confirmed alternate release did not allow switch'
pass 'broken old path releases exact Native ledger IP via healthy USB'
reset; TEST_LOGOUT_DEVICE_FAIL=phy0-sta0; TEST_USB_ONLINE=0; export TEST_LOGOUT_DEVICE_FAIL TEST_USB_ONLINE
run_rc 1 "$BIN/native-best" switch radio2
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'unconfirmed release allowed login'
pass 'unhealthy backup cannot bypass old-session release guard'
reset; TEST_NATIVE_ONLINE=0; TEST_PING_FAIL=1; TEST_DHCP_RECOVERY=1; export TEST_NATIVE_ONLINE TEST_PING_FAIL TEST_DHCP_RECOVERY
mw_now="$(awk '{print int($1)}' /proc/uptime)"; printf '%s\n' "$mw_now" > "$TEST_ROOT/tmp/native-watchdog/last_scan"
run_rc 0 "$BIN/native-watchdog"
grep -q '^ifdown wan1' "$TEST_ROOT/trace" || fail 'unreachable gateway left stale DHCP'
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'DHCP reacquire blindly authenticated'
grep -q '10.1.1.10 phy0-sta0' "$TEST_ROOT/etc/scut-multiwan/native.session" || fail 'DHCP reacquire altered journal'
pass 'unreachable gateway DHCP reacquire preserves session and verifies public health'
reset; TEST_NATIVE_ONLINE=0; TEST_REDIRECT=; export TEST_NATIVE_ONLINE TEST_REDIRECT
mw_now="$(awk '{print int($1)}' /proc/uptime)"; printf '%s\n' "$mw_now" > "$TEST_ROOT/tmp/native-watchdog/last_scan"
run_rc 0 "$BIN/native-watchdog"
! grep -q '^ifdown' "$TEST_ROOT/trace" || fail 'ordinary public outage renewed DHCP'
pass 'reachable gateway public timeout does not trigger DHCP reacquire'
reset; TEST_NATIVE_ONLINE=0; TEST_PING_FAIL=1; TEST_REDIRECT=; export TEST_NATIVE_ONLINE TEST_PING_FAIL TEST_REDIRECT
mw_now="$(awk '{print int($1)}' /proc/uptime)"; printf '%s\n' "$mw_now" > "$TEST_ROOT/tmp/native-watchdog/last_scan"
printf '%s\n' "$mw_now" > "$TEST_ROOT/tmp/native-watchdog/dhcp.radio0"
run_rc 0 "$BIN/native-watchdog"
! grep -q '^ifdown' "$TEST_ROOT/trace" || fail 'DHCP recovery cooldown ignored'
pass 'unreachable gateway recovery cannot repeat within five minutes'
reset; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
TEST_NATIVE_ONLINE=0; TEST_PING_FAIL=1; export TEST_NATIVE_ONLINE TEST_PING_FAIL
run_rc 0 "$BIN/native-watchdog"
! grep -q '^ifdown' "$TEST_ROOT/trace" || fail 'holiday night restarted DHCP'
pass 'night watchdog never enters daytime DHCP recovery'
reset
printf '999999999\n' > "$TEST_ROOT/tmp/native-watchdog/retry_scan"
printf '5\n' > "$TEST_ROOT/tmp/native-watchdog/scan_failures"
run_rc 0 "$BIN/native-best" switch radio2
[ ! -e "$TEST_ROOT/tmp/native-watchdog/retry_scan" ] && [ ! -e "$TEST_ROOT/tmp/native-watchdog/scan_failures" ] || fail 'successful recovery kept failure backoff'
[ ! -e "$TEST_ROOT/tmp/native-watchdog/last_scan" ] || fail 'manual switch falsely marked survey'
pass 'verified successful switch clears earlier failed recovery backoff without fabricating a survey'
