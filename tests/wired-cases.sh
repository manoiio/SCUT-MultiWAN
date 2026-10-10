# Isolated router BusyBox tests, with fictitious wired IP and credentials.
wired_fixture() {
    TEST_EPOCH=1791432000; export TEST_EPOCH
    mkdir -p "$TEST_ROOT/sys/wan" "$TEST_ROOT/tmp/scut-multiwan-locks"
    printf '1\n' > "$TEST_ROOT/sys/wan/carrier"
    printf "WIRED_ENABLE=1\nWIRED_IP=10.4.4.40\n" > "$TEST_ROOT/etc/scut-wired.conf"
    printf 'none wan\n' > "$TEST_ROOT/etc/scut-multiwan/wired.session"
    printf 'none 0 0 0\n' > "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
    mkdir -p "$TEST_ROOT/proc/999999"
    printf '999999 12345\n' > "$TEST_ROOT/tmp/scut-wired-ready"
    printf '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 12345\n' > "$TEST_ROOT/proc/999999/stat"
}
gate() {
    (exec 9>>"$TEST_ROOT/tmp/scut-multiwan-locks/portal"; flock -n 9 || exit 75; "$BIN/scut-wired-gate" "$1")
}
reset; wired_fixture; TEST_WIRED_ONLINE=1; export TEST_WIRED_ONLINE
run_rc 0 "$BIN/dualwan-refresh" apply
grep -q 'weight 1 nexthop via 10.2.2.1 dev phy3-sta0 weight 1 nexthop via 10.4.4.1 dev wan weight 1' "$TEST_ROOT/trace" || fail 'third nexthop absent'
! grep -qE 'rule del|route flush' "$TEST_ROOT/trace" || fail 'three-WAN refresh removed healthy policy'
pass 'three healthy WANs use table 103 with equal weights'
reset; wired_fixture; TEST_WIRED_ONLINE=0; export TEST_WIRED_ONLINE
run_rc 0 "$BIN/dualwan-refresh" apply
! grep -q 'default.*dev wan ' "$TEST_ROOT/trace" || fail 'unhealthy wired in default'
pass 'unhealthy wired link retains existing wireless ECMP'
reset; wired_fixture; TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0; TEST_WIRED_ONLINE=1; export TEST_NATIVE_ONLINE TEST_USB_ONLINE TEST_WIRED_ONLINE
run_rc 0 "$BIN/dualwan-refresh" apply
grep -q 'default via 10.4.4.1 dev wan' "$TEST_ROOT/trace" || fail 'wired-only fallback'
pass 'wired-only healthy fallback works'
reset; wired_fixture; TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0; export TEST_NATIVE_ONLINE TEST_USB_ONLINE
run_rc 1 "$BIN/dualwan-refresh" apply
pass 'all three down removes policy'
reset; wired_fixture; TEST_WIRED_ONLINE=1; TEST_ROUTE_FAIL=1; export TEST_WIRED_ONLINE TEST_ROUTE_FAIL
run_rc 1 "$BIN/dualwan-refresh" apply
pass 'three-way installation error fails closed'
reset; wired_fixture; run_rc 75 "$BIN/scut-wired-gate" prepare
pass 'wired admission requires actual inherited global lock'
reset; wired_fixture; run_rc 75 "$BIN/scut-wired-gate" release-window
pass 'release discovery retry requires the inherited real Portal lock'
reset; wired_fixture; TEST_CLOCK='00 05 55'; export TEST_CLOCK
before="$(sha256sum "$TEST_ROOT/etc/scut-multiwan/wired.session" "$TEST_ROOT/etc/scut-multiwan/wired.night-budget")"
run_rc 76 gate release-window
[ "$before" = "$(sha256sum "$TEST_ROOT/etc/scut-multiwan/wired.session" "$TEST_ROOT/etc/scut-multiwan/wired.night-budget")" ] || fail 'release guard changed durable state'
pass 'release retry stops before quiet boundary without consuming an attempt'
reset; wired_fixture; TEST_CLOCK='00 05 50'; export TEST_CLOCK
run_rc 0 gate release-window
pass 'release retry is permitted with sufficient active time remaining'
reset; wired_fixture; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-08; TEST_WEEKDAY=4; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 76 gate release-window
pass 'release retries cannot authenticate or release during working-night silence'
reset; wired_fixture; TEST_CLOCK='00 24 59'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 76 gate prepare
read stamp count last block < "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
[ "$stamp" = none ] || fail 'protected interval consumed attempt'
pass 'wired authentication respects midnight protection'
reset; wired_fixture; TEST_CLOCK='00 25 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 0 gate prepare
run_rc 76 gate prepare
TEST_EPOCH=$((TEST_EPOCH+900)); export TEST_EPOCH
run_rc 0 gate prepare
TEST_EPOCH=$((TEST_EPOCH+900)); export TEST_EPOCH
run_rc 76 gate prepare
pass 'wired night attempts persist, require 15 minutes and stop at two'
reset; wired_fixture; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
printf '2026-10-06 2 0 0\n' > "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
printf '2026-10-06 4\n' > "$TEST_ROOT/etc/scut-multiwan/wired.limit-override"
run_rc 0 gate prepare
read stamp count last block < "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
[ "$count" = 3 ] || fail 'temporary cap reset existing attempts'
run_rc 76 gate prepare
rm "$TEST_ROOT/etc/scut-multiwan/wired.limit-override"
printf '2026-10-06 3 0 0\n' > "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
run_rc 76 gate prepare
TEST_CLOCK='07 00 00'; export TEST_CLOCK
run_rc 0 gate prepare
pass 'approved temporary wired cap preserves attempts/cooldown and expires safely'
reset; wired_fixture; printf '2026-10-06 2 0 0\n' > "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
TEST_CLOCK='07 00 00'; export TEST_CLOCK
run_rc 0 gate prepare
pass '07:00 wired recovery bypasses night attempt cap'
reset; wired_fixture; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 0 gate prepare; run_rc 0 gate uncertain
TEST_EPOCH=$((TEST_EPOCH+900)); export TEST_EPOCH
run_rc 76 gate prepare
pass 'uncertain wired release blocks the remaining night attempts'
reset; wired_fixture; printf 'broken\n' > "$TEST_ROOT/etc/scut-multiwan/wired.session"
run_rc 75 gate prepare
pass 'corrupt wired session fails closed'
reset; wired_fixture; printf '10.9.9.9 wan\n' > "$TEST_ROOT/etc/scut-multiwan/wired.session"
run_rc 75 gate prepare
pass 'changed wired IP cannot bypass release protection'
reset; wired_fixture; TEST_WIRED_IP=10.4.4.41; export TEST_WIRED_IP
run_rc 75 gate prepare
pass 'assigned wired IP must match before authentication'
reset; wired_fixture; printf '0\n' > "$TEST_ROOT/sys/wan/carrier"
run_rc 77 gate prepare
pass 'unplugged wired port cannot authenticate'
reset; wired_fixture
run_rc 0 "$BIN/scut-wired-gate" preflight
read stamp count last block < "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
[ "$stamp" = none ] || fail 'preflight consumed durable attempt'
pass 'unlocked preflight is read-only and consumes no attempt'
reset; wired_fixture; run_rc 1 gate needs-release; run_rc 0 gate journal; run_rc 0 gate needs-release
read stored dev < "$TEST_ROOT/etc/scut-multiwan/wired.session"
[ "$stored" = 10.4.4.40 ] && [ "$dev" = wan ] || fail 'journal missing before write'
run_rc 0 gate released; run_rc 1 gate needs-release
pass 'wired journal records target before login and clears only after release'
reset; wired_fixture; TEST_WIRED_ONLINE=1; export TEST_WIRED_ONLINE
rm "$TEST_ROOT/tmp/scut-wired-ready"
run_rc 0 "$BIN/dualwan-refresh" apply
! grep -q 'default.*dev wan ' "$TEST_ROOT/trace" || fail 'exited protocol engine left route'
pass 'wired engine readiness is required even when HTTPS works'
reset; wired_fixture; TEST_WIRED_ONLINE=1; export TEST_WIRED_ONLINE
printf '999999 54321\n' > "$TEST_ROOT/tmp/scut-wired-ready"
run_rc 0 "$BIN/dualwan-refresh" apply
! grep -q 'default.*dev wan ' "$TEST_ROOT/trace" || fail 'PID reuse accepted'
pass 'wired readiness rejects reused process IDs'
reset; wired_fixture; run_rc 75 gate challenge; run_rc 0 gate journal; run_rc 0 gate challenge
TEST_CLOCK='00 24 59'; TEST_DATE=2026-10-06; TEST_WEEKDAY=2; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 0 gate challenge
TEST_DATE=2026-10-08; TEST_WEEKDAY=4; TEST_CLOCK='01 00 00'; export TEST_DATE TEST_WEEKDAY TEST_CLOCK
run_rc 76 gate challenge
pass 'existing EAP challenge allows holiday protection but refuses working nights'
reset; wired_fixture
rm -f "$TEST_ROOT/mock-engine.pid"
"$LIB/wired-run" > "$TEST_ROOT/last-output" 2>&1 & wrapper=$!
round=0
while [ ! -f "$TEST_ROOT/mock-engine.pid" ] && [ "$round" -lt 5 ]; do /bin/sleep 1; round=$((round+1)); done
[ -f "$TEST_ROOT/mock-engine.pid" ] || { kill "$wrapper" 2>/dev/null; fail 'wired engine did not launch'; }
engine="$(cat "$TEST_ROOT/mock-engine.pid")"
kill -TERM "$wrapper"; wait "$wrapper"
! kill -0 "$engine" 2>/dev/null || fail 'service stop left authentication child running'
grep -q engine-stopped "$TEST_ROOT/trace" || fail 'stop signal was not forwarded'
pass 'procd wrapper stop terminates protocol child without orphaning it'
