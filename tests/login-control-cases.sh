# Appended to the isolated BusyBox suite; only public fixtures.
reset
CONTROL="$TEST_ROOT/usr/lib/scut-multiwan/wireless-control.sh"
EMPTY='dr1002({"result":0,"msg":"获取用户在线信息数据为空！"});'
export EMPTY
/bin/sh -c '. "$1"; mw_portal_empty "$EMPTY"' sh "$COMMON" || fail 'known offline response'
pass 'known exact offline message parsed without printing provider data'
for bad in '{"result":0}' '{"result":1,"msg":"获取用户在线信息数据为空！"}' 'dr1002({"result":0,"msg":"other"});' 'dr1002({"result":0,"msg":"获取用户在线信息数据为空！"'; do
 if /bin/sh -c '. "$1"; mw_portal_empty "$2"' sh "$COMMON" "$bad"; then fail 'ambiguous response accepted'; fi
done
pass 'generic failures, online results and truncated replies cannot release a session'
echo '10.1.1.10 phy0-sta0' > "$TEST_ROOT/etc/scut-multiwan/native.session"
/bin/sh -c '. "$1"; mw_portal_lock 0 || exit; mw_confirm_absent native phy0-sta0 10.1.1.10 "$EMPTY"' sh "$COMMON"
[ "$?" = 75 ] || fail 'automatic confirmation not paused'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.1.1.10 phy0-sta0' ] || fail 'automatic absence erased journal'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.login-paused")" = vanished ] || fail 'missing durable pause'
[ "$(grep -c '^READ_ONLY_ONLINE' "$TEST_ROOT/trace")" = 2 ] || fail 'two readonly checks not made'
pass 'confirmed absence pauses automatically and retains journal'
run_rc 75 "$BIN/campus-portal-login" phy0-sta0
run_rc 75 "$BIN/native-watchdog"
run_rc 75 "$BIN/native-best" apply
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'paused caller submitted login'
pass 'Native login, watchdog and selection reject automatic admission while paused'
: > "$TEST_ROOT/trace"
MW_MANUAL_LOGIN=1 /bin/sh -c '. "$1"; mw_portal_lock 0 || exit; mw_confirm_absent native phy0-sta0 10.1.1.10 "$EMPTY"' sh "$COMMON" || fail 'explicit offline release'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = 'none none' ] || fail 'manual exact absence confirmation'
pass 'explicit manual admission clears only the twice-confirmed exact absent record'
echo '10.1.1.10 phy0-sta0' > "$TEST_ROOT/etc/scut-multiwan/native.session"
for flag in TEST_ABSENT_QUERY_FAIL TEST_ABSENT_QUERY_ONLINE; do
 export "$flag=1"
 if MW_MANUAL_LOGIN=1 /bin/sh -c '. "$1"; mw_portal_lock 0 || exit; mw_confirm_absent native phy0-sta0 10.1.1.10 "$EMPTY"' sh "$COMMON"; then fail 'unsafe query accepted'; fi
 unset "$flag"
 [ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.1.1.10 phy0-sta0' ] || fail 'unsafe query changed journal'
done
pass 'timeout and contradictory online query retain journal during manual admission'
if MW_MANUAL_LOGIN=1 /bin/sh -c '. "$1"; mw_portal_lock 0 || exit; mw_confirm_absent native phy2-sta0 10.1.1.10 "$EMPTY"' sh "$COMMON"; then fail 'different source released old target'; fi
pass 'different source IP cannot confirm absence of a stale recorded IP'
rm -f "$TEST_ROOT/etc/scut-multiwan/native.login-paused"
touch "$TEST_ROOT/etc/scut-multiwan/morning-random.enabled"
/bin/sh -c '. "$1"; MW_DATE=2026-10-08; mw_morning_time || exit; printf "%s %s %s\n" "$MW_NATIVE_START" "$MW_USB_START" "$MW_WAN_START"' sh "$COMMON" > "$TEST_ROOT/draw.first" || fail 'morning draw'
/bin/sh -c '. "$1"; MW_DATE=2026-10-08; mw_morning_time || exit; printf "%s %s %s\n" "$MW_NATIVE_START" "$MW_USB_START" "$MW_WAN_START"' sh "$COMMON" > "$TEST_ROOT/draw.second" || fail 'morning redraw'
cmp -s "$TEST_ROOT/draw.first" "$TEST_ROOT/draw.second" || fail 'same day redrawn'
pass 'three distinct independent 07:00-07:40 draws persist for the local date'
echo '2026-10-08 25800 26400 27000' > "$TEST_ROOT/etc/scut-multiwan/morning-time"
TEST_CLOCK='07 05 00' run_rc 76 "$BIN/native-watchdog"
TEST_CLOCK='07 11 00' /bin/sh -c '. "$1"; mw_login_paused native' sh "$COMMON" || fail 'Native due'
TEST_CLOCK='07 11 00' /bin/sh -c '. "$1"; mw_login_paused usb' sh "$COMMON"
[ "$?" = 76 ] || fail 'USB starts at Native time'
TEST_CLOCK='07 21 00' /bin/sh -c '. "$1"; mw_login_paused wan' sh "$COMMON"
[ "$?" = 76 ] || fail 'wired starts at USB time'
pass 'watchdogs and login guards wait for each independent morning time'
echo '2026-10-08 25800 25800 27000' > "$TEST_ROOT/etc/scut-multiwan/morning-time"
if /bin/sh -c '. "$1"; MW_DATE=2026-10-08; mw_morning_time' sh "$COMMON"; then fail 'duplicate times accepted'; fi
pass 'corrupt duplicate startup times fail closed'
rm -f "$TEST_ROOT/etc/scut-multiwan/morning-random.enabled" "$TEST_ROOT/etc/scut-multiwan/morning-time"
run_rc 2 "$TEST_ROOT/usr/libexec/scut-lan-link-action" native 'login;echo bad'
run_rc 2 "$TEST_ROOT/usr/libexec/scut-lan-link-action" radio0 login
pass 'manual RPC accepts only exact slot and operation enums'

/bin/sh -c '. "$1"; mw_pause_login usb vanished' sh "$COMMON" || fail 'USB hold'
: > "$TEST_ROOT/trace"
run_rc 75 "$BIN/campus-usb-login" phy3-sta0
run_rc 75 "$BIN/usb-watchdog"
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'USB hold submitted login'
pass 'USB automatic admission also stops before Portal requests'
/bin/sh -c '. "$1"; mw_pause_login wan manual' sh "$COMMON" || fail 'wired hold'
run_rc 75 "$TEST_ROOT/usr/lib/scut-multiwan/wired-run"
! grep -q 'engine' "$TEST_ROOT/trace" || fail 'wired manual stop restarted engine'
pass 'manual wired logout survives procd retries without starting authentication'
rm -f "$TEST_ROOT/etc/scut-multiwan/usb.login-paused" "$TEST_ROOT/etc/scut-multiwan/wan.login-paused"

reset
run_rc 0 "$BIN/scut-lan-links" action usb login
n=0
while [ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result" 2>/dev/null)" = running ] && [ "$n" -lt 20 ]; do busybox sleep 1; n=$((n+1)); done
[ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result")" = login-ok ] || fail 'detached manual worker did not complete'
[ ! -f "$TEST_ROOT/etc/scut-multiwan/usb.login-paused" ] || fail 'verified login left hold'
pass 'detached worker survives command return without unavailable nohup and verifies login'


reset
for slot in native usb wan; do
 /bin/sh -c '. "$1"; mw_pause_login "$2" logout' sh "$COMMON" "$slot" || fail 'logout hold'
done
run_rc 75 "$BIN/campus-portal-login" phy0-sta0
run_rc 75 "$BIN/native-watchdog"
run_rc 75 "$BIN/campus-usb-login" phy3-sta0
run_rc 75 "$BIN/usb-watchdog"
run_rc 75 "$TEST_ROOT/usr/lib/scut-multiwan/wired-run"
! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'automatic same-day login after manual logout'
pass 'manual logout holds all three automatic authentication entry points'
rm -f "$TEST_ROOT/etc/scut-multiwan/native.login-paused" "$TEST_ROOT/etc/scut-multiwan/usb.login-paused" "$TEST_ROOT/etc/scut-multiwan/wan.login-paused"
busybox sleep 1
run_rc 0 "$BIN/scut-lan-links" action usb logout
n=0
while [ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result" 2>/dev/null)" = running ] && [ "$n" -lt 20 ]; do busybox sleep 1; n=$((n+1)); done
[ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result")" = logout-ok ] || fail 'manual logout worker'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/usb.login-paused")" = logout ] || fail 'manual logout marker'
run_rc 75 "$BIN/usb-watchdog"
pass 'confirmed explicit logout persists its hold and cannot be followed by watchdog login'
busybox sleep 1
touch "$TEST_ROOT/etc/scut-multiwan/morning-random.enabled"
printf '2026-10-08 25800 26400 27000\n' > "$TEST_ROOT/etc/scut-multiwan/morning-time"
before=$(grep -c '^LOGIN' "$TEST_ROOT/trace")
TEST_DATE='2026-10-08' TEST_CLOCK='07 40 00' run_rc 0 "$BIN/scut-morning-start" slot usb
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/usb.morning-claimed")" = 2026-10-08 ] || fail 'logout did not block same-day morning'
[ "$(grep -c '^LOGIN' "$TEST_ROOT/trace")" = "$before" ] || fail 'morning login on manual logout date'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/usb.login-paused")" = logout ] || fail 'same-day morning cleared logout hold'
pass 'manual logout also cancels a not-yet-run morning attempt on the same date'
printf '2026-10-09 25800 26400 27000\n' > "$TEST_ROOT/etc/scut-multiwan/morning-time"
TEST_DATE='2026-10-09' TEST_CLOCK='07 40 00' run_rc 0 "$BIN/scut-morning-start" slot usb
n=0
while [ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result" 2>/dev/null)" = running ] && [ "$n" -lt 20 ]; do busybox sleep 1; n=$((n+1)); done
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/usb.morning-claimed")" = 2026-10-09 ] || fail 'next-day claim'
[ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result")" = login-ok ] || fail 'next morning failed to resume explicit logout'
[ ! -e "$TEST_ROOT/etc/scut-multiwan/usb.login-paused" ] || fail 'verified next morning retained hold'
before=$(grep -c '^LOGIN' "$TEST_ROOT/trace")
TEST_DATE='2026-10-09' TEST_CLOCK='07 40 00' run_rc 0 "$BIN/scut-morning-start" slot usb
[ "$(grep -c '^LOGIN' "$TEST_ROOT/trace")" = "$before" ] || fail 'repeated daily authentication'
pass 'next-day morning attempts once and can resume a manually logged-out session'

reset
export TEST_DATE=2026-10-08 TEST_CLOCK='08 05 00'
run_rc 0 "$BIN/scut-lan-links" action usb logout
n=0
while [ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result" 2>/dev/null)" = running ] && [ "$n" -lt 20 ]; do busybox sleep 1; n=$((n+1)); done
[ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result")" = logout-ok ] || fail '08:05 manual logout'
run_rc 75 "$BIN/usb-watchdog"
busybox sleep 1
run_rc 0 "$BIN/scut-lan-links" action usb login
n=0
while [ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result" 2>/dev/null)" = running ] && [ "$n" -lt 20 ]; do busybox sleep 1; n=$((n+1)); done
[ "$(cat "$TEST_ROOT/var/run/scut-lan/usb.job.result")" = login-ok ] || fail 'same-day manual login'
[ ! -e "$TEST_ROOT/etc/scut-multiwan/usb.login-paused" ] || fail 'same-day verified login retained hold'
busybox sleep 1
run_rc 0 "$BIN/usb-watchdog"
pass '08:05 manual logout then verified manual login resumes watchdog on the same day'
