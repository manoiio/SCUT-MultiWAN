# Retry scheduling is tested separately from real worker/session safety fixtures.
reset
MORNING="$BIN/scut-morning-start-fixture"
export TEST_DATE=2026-10-09 TEST_CLOCK='07 40 00'
touch "$TEST_ROOT/etc/scut-multiwan/morning-random.enabled"
printf '2026-10-09 25800 26400 27000\n' > "$TEST_ROOT/etc/scut-multiwan/morning-time"
for slot in native usb wan; do run_rc 0 "$MORNING" due "$slot"; done
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = 3 ] || fail 'three initial admissions'
for slot in native usb wan; do
 [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.morning-state")" = '2026-10-09 1 28200 failed' ] || fail 'first durable retry state'
done
pass 'three independent morning lines persist their first failed attempt and cooldown'
TEST_CLOCK='07 45 00'; export TEST_CLOCK
for slot in native usb wan; do run_rc 0 "$MORNING" due "$slot"; done
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = 3 ] || fail 'early retry'
TEST_CLOCK='07 50 00'; export TEST_CLOCK
for slot in native usb wan; do run_rc 0 "$MORNING" due "$slot"; done
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = 6 ] || fail 'second admission'
pass 'failed admissions wait ten minutes before retrying all three lines'
run_rc 0 "$MORNING" due native
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = 6 ] || fail 'restart reset cooldown'
TEST_CLOCK='08 00 00'; export TEST_CLOCK
run_rc 0 "$MORNING" due native
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.morning-state")" = '2026-10-09 3 29400 failed' ] || fail 'restart reset count'
pass 'a new scheduler process preserves the prior date, count and cooldown'
TEST_CLOCK='08 10 00'; TEST_MORNING_ONLINE=native; export TEST_CLOCK TEST_MORNING_ONLINE
before=$(grep -c '^MORNING' "$TEST_ROOT/trace")
run_rc 0 "$MORNING" due native
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = "$before" ] || fail 'healthy line authenticated again'
pass 'publicly healthy lines do not consume authentication attempts'
unset TEST_MORNING_ONLINE
/bin/sh -c '. "$1"; mw_pause_login native logout' sh "$COMMON" || fail 'manual cancellation'
TEST_CLOCK='08 20 00'; export TEST_CLOCK
run_rc 0 "$MORNING" due native
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = "$before" ] || fail 'same-day logout ignored'
pass 'manual logout cancels the remaining morning retries on that local date'
TEST_DATE=2026-10-10; TEST_CLOCK='07 40 00'; export TEST_DATE TEST_CLOCK
printf '2026-10-10 25800 26400 27000\n' > "$TEST_ROOT/etc/scut-multiwan/morning-time"
run_rc 0 "$MORNING" due native
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.morning-state")" = '2026-10-10 1 28200 failed' ] || fail 'next-day restart'
pass 'the next local date renews its attempt budget without erasing session journals'
TEST_CLOCK='09 00 00'; export TEST_CLOCK
before=$(grep -c '^MORNING' "$TEST_ROOT/trace")
for slot in native usb wan; do run_rc 0 "$MORNING" due "$slot"; done
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = "$before" ] || fail 'after deadline admission'
MW_MORNING_LOGIN=1 MW_MORNING_DAY=2026-10-10 /bin/sh -c '. "$1"; mw_require_active 0' sh "$COMMON"
[ "$?" = 76 ] || fail 'worker deadline bypass'
pass '09:00 blocks both new scheduler admissions and in-progress worker mutation guards'
TEST_CLOCK='08 40 00'; export TEST_CLOCK
printf '2026-10-10 12 30000 failed\n' > "$TEST_ROOT/etc/scut-multiwan/native.morning-state"
run_rc 0 "$MORNING" due native
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = "$before" ] || fail 'budget exceeded'
printf '2026-10-10 corrupted\n' > "$TEST_ROOT/etc/scut-multiwan/native.morning-state"
run_rc 75 "$MORNING" due native
pass 'twelve-attempt budget and malformed persistent retry state fail closed'
rm -f "$TEST_ROOT/etc/scut-multiwan/native.morning-state"
TEST_MORNING_RC=75; export TEST_MORNING_RC
run_rc 0 "$MORNING" due native
grep -q ' deferred$' "$TEST_ROOT/etc/scut-multiwan/native.morning-state" || fail 'busy outcome'
before=$(grep -c '^MORNING' "$TEST_ROOT/trace")
run_rc 0 "$MORNING" due native
[ "$(grep -c '^MORNING' "$TEST_ROOT/trace")" = "$before" ] || fail 'busy loop'
pass 'lock/policy deferral retains its cooldown instead of spinning'

reset
TEST_BEST_RC=23; export TEST_BEST_RC
run_rc 23 "$BIN/scut-lan-links-select-fixture" worker native login
grep -q 'stage=native-select rc=23' "$TEST_ROOT/etc/scut-multiwan/native.last-detail" || fail 'lost Native return code'
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'selection failure still authenticated'
! grep -q 'test-password\|PRIVATE_FIXTURE_BODY' "$TEST_ROOT/etc/scut-multiwan/native.last-detail" || fail 'sensitive detail'
pass 'Native worker retains original stage/code without credential or response capture'
reset
TEST_NO_DHCP=1; TEST_DHCP_RECOVERY=1; export TEST_NO_DHCP TEST_DHCP_RECOVERY
rm -f "$TEST_ROOT/etc/scut-multiwan/native.login-paused"
run_rc 0 "$BIN/native-best" apply
grep -q '^ifup wan1' "$TEST_ROOT/trace" || fail 'current DHCP not recovered'
! grep -q '^LOGIN\|^LOGOUT' "$TEST_ROOT/trace" || fail 'DHCP-only repair authenticated'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.1.1.10 phy0-sta0' ] || fail 'DHCP repair erased journal'
pass 'the already-selected Native radio recovers missing DHCP without authenticating or clearing its journal'
reset
TEST_NO_DHCP=1; export TEST_NO_DHCP
rm -f "$TEST_ROOT/etc/scut-multiwan/native.login-paused"
run_rc 1 "$BIN/native-best" apply
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'failed DHCP recovery authenticated'
pass 'current-radio DHCP timeout remains bounded and stops authentication'
