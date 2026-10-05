# Appended to the isolated BusyBox runner; uses its reset/run_rc/pass helpers.
LIB="${COMMON%/*}"
night() { TEST_CLOCK='00 25 00'; TEST_DATE=2026-10-04; TEST_WEEKDAY=7; export TEST_CLOCK TEST_DATE TEST_WEEKDAY; }

reset; TEST_CLOCK='00 25 00'; TEST_DATE=2026-10-10; TEST_WEEKDAY=6; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 76 "$BIN/campus-portal-login" phy0-sta0; notrace workweekend
pass 'official make-up Saturday stays quiet'
reset; TEST_CLOCK='01 00 00'; TEST_DATE=2026-10-11; TEST_WEEKDAY=7; export TEST_CLOCK TEST_DATE TEST_WEEKDAY
run_rc 0 "$BIN/native-watchdog"; grep -q '^HTTPS ' "$TEST_ROOT/trace" || fail 'rest Sunday no check'
! grep -qE 'LOGIN|LOGOUT|SCAN|RATE|wifi |iw-create' "$TEST_ROOT/trace" || fail 'night optimized a healthy link'
pass 'ordinary rest Sunday allows low-cost health check without scanning or tuning'
reset; night; TEST_DATE=2026-10-05; TEST_WEEKDAY=1; export TEST_DATE TEST_WEEKDAY
run_rc 0 "$BIN/native-watchdog"; grep -q '^HTTPS ' "$TEST_ROOT/trace" || fail 'holiday Monday blocked'
pass 'official weekday holiday allows overnight health check'
reset; night; TEST_CLOCK='00 24 59'; export TEST_CLOCK
run_rc 76 "$BIN/campus-portal-login" phy0-sta0; notrace protection
run_rc 0 "$BIN/dualwan-refresh" apply
! grep -qE 'LOGIN|LOGOUT|SCAN|wifi ' "$TEST_ROOT/trace" || fail 'route protection changed authentication/radio'
pass '00:24:59 blocks login but allows holiday route-only health convergence'
reset; night
run_rc 76 "$BIN/native-best" apply; run_rc 76 "$BIN/native-best" switch radio2; run_rc 76 "$BIN/qca-radio-survey"
notrace scans; pass 'holiday night never starts an optimization scan/switch'
reset; night; TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=1; export TEST_NATIVE_ONLINE TEST_USB_ONLINE
run_rc 0 "$BIN/dualwan-refresh" apply
grep -q 'default via 10.2.2.1 dev phy3-sta0' "$TEST_ROOT/trace" || fail 'night single-link policy'
! grep -qE 'LOGIN|LOGOUT|SCAN' "$TEST_ROOT/trace" || fail 'route-only invoked recovery'
pass 'night route refresh keeps only the healthy USB link'
reset; night; TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0; export TEST_NATIVE_ONLINE TEST_USB_ONLINE
run_rc 1 "$BIN/dualwan-refresh" apply
grep -q 'rule del pref 103' "$TEST_ROOT/trace" || fail 'both down left policy'
pass 'both night WANs down removes policy without authentication'
reset; night; TEST_PRIMARY_FAIL=1; export TEST_PRIMARY_FAIL
run_rc 0 "$BIN/native-watchdog"
! grep -qE 'LOGIN|LOGOUT' "$TEST_ROOT/trace" || fail 'single HTTPS site failure caused auth'
pass 'independent HTTPS fallback prevents login on primary-site failure'
reset; night; TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 0 "$BIN/native-watchdog"
grep -q '^LOGIN phy0-sta0' "$TEST_ROOT/trace" || fail 'no recovery after 00:25'
read stamp attempts when blocked < "$TEST_ROOT/etc/scut-multiwan/native.night-budget"
[ "$attempts" = 1 ] || fail 'attempt not persisted'
! grep -qE 'SCAN|wifi ' "$TEST_ROOT/trace" || fail 'recovery scanned/restarted wifi'
pass '00:25 recovers expired authentication and journals an attempt before any write'
reset; night; TEST_NATIVE_ONLINE=0; TEST_AFTER_LOGIN_ONLINE=0; export TEST_NATIVE_ONLINE TEST_AFTER_LOGIN_ONLINE
run_rc 1 "$BIN/campus-portal-login" phy0-sta0
read stamp attempts when blocked < "$TEST_ROOT/etc/scut-multiwan/native.night-budget"
[ "$attempts" = 1 ] || fail 'successful response without Internet not counted'
: > "$TEST_ROOT/trace"; run_rc 76 "$BIN/campus-portal-login" phy0-sta0
! grep -qE '^LOGIN|^LOGOUT' "$TEST_ROOT/trace" || fail 'cooldown wrote Portal'
TEST_EPOCH=1791432900; export TEST_EPOCH
run_rc 1 "$BIN/campus-portal-login" phy0-sta0
read stamp attempts when blocked < "$TEST_ROOT/etc/scut-multiwan/native.night-budget"
[ "$attempts" = 2 ] || fail 'second attempt count'
TEST_EPOCH=1791433800; export TEST_EPOCH; : > "$TEST_ROOT/trace"
run_rc 76 "$BIN/campus-portal-login" phy0-sta0
! grep -qE '^LOGIN|^LOGOUT' "$TEST_ROOT/trace" || fail 'quota bypass after restart-equivalent fresh process'
pass 'Portal success without HTTPS, 15-minute cooldown and durable two-attempt cap'
TEST_CLOCK='07 00 00'; TEST_AFTER_LOGIN_ONLINE=1; export TEST_CLOCK TEST_AFTER_LOGIN_ONLINE
run_rc 0 "$BIN/campus-portal-login" phy0-sta0
pass '07:00 daytime authentication is not blocked by night quota'
reset; night; TEST_NATIVE_ONLINE=0; TEST_FAIL_LOGOUT_IP=167837962; export TEST_NATIVE_ONLINE TEST_FAIL_LOGOUT_IP
run_rc 1 "$BIN/campus-portal-login" phy0-sta0
TEST_EPOCH=1791432900; TEST_FAIL_LOGOUT_IP=never; export TEST_EPOCH TEST_FAIL_LOGOUT_IP; : > "$TEST_ROOT/trace"
run_rc 76 "$BIN/campus-portal-login" phy0-sta0
! grep -qE '^LOGIN|^LOGOUT' "$TEST_ROOT/trace" || fail 'uncertain old release retried'
pass 'old-session release failure blocks subsequent night recovery'
reset; night; TEST_USB_ONLINE=0; TEST_LOGIN_TIMEOUT=1; export TEST_USB_ONLINE TEST_LOGIN_TIMEOUT
run_rc 1 "$BIN/campus-usb-login" phy3-sta0
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/usb.session")" = '10.2.2.20 phy3-sta0' ] || fail 'timeout discarded occupied slot'
read stamp attempts when blocked < "$TEST_ROOT/etc/scut-multiwan/usb.night-budget"
[ "$attempts" = 1 ] || fail 'USB timeout not counted'
pass 'USB timeout consumes attempt and retains occupied session journal'
reset; night; TEST_NATIVE_ONLINE=0; TEST_REDIRECT='https://elsewhere.invalid/'; export TEST_NATIVE_ONLINE TEST_REDIRECT
run_rc 1 "$BIN/campus-portal-login" phy0-sta0
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.night-budget")" = 'none 0 0 0' ] || fail 'non-Portal consumed auth attempt'
! grep -qE '^LOGIN|^LOGOUT' "$TEST_ROOT/trace" || fail 'wrong-host auth'
pass 'plain failure without exact Portal redirect does not spend auth budget'
reset; night; rm "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt"
run_rc 76 "$BIN/dualwan-refresh" apply; notrace unknowncalendar
pass 'missing annual cache fails closed even on Sunday'
reset; night; TEST_DATE=2027-01-02; TEST_WEEKDAY=6; export TEST_DATE TEST_WEEKDAY
run_rc 76 "$BIN/dualwan-refresh" apply; notrace unknownyear
pass 'unpublished next-year weekend is not guessed'
reset; night; TEST_DATE=1970-01-01; export TEST_DATE
run_rc 76 "$BIN/campus-portal-login" phy0-sta0; notrace invalidclock
pass 'uninitialized router clock fails closed'
reset; night
run_rc 0 "$BIN/scut-night-control" quiet 2026-10-04
run_rc 76 "$BIN/campus-portal-login" phy0-sta0
notrace overridequiet
run_rc 0 "$BIN/scut-night-control" clear
run_rc 0 "$BIN/campus-portal-login" phy0-sta0
pass 'date override quiet takes precedence; clear restores calendar without touching ledgers'
reset; TEST_CLOCK='00 25 00'; export TEST_CLOCK
run_rc 0 "$BIN/scut-night-control" allow 2026-10-08
run_rc 0 "$BIN/campus-portal-login" phy0-sta0
TEST_DATE=2026-10-09; TEST_WEEKDAY=5; export TEST_DATE TEST_WEEKDAY; : > "$TEST_ROOT/trace"
run_rc 76 "$BIN/campus-portal-login" phy0-sta0; notrace expire
pass 'allow override expires across midnight and retains ordinary-workday silence'
reset; night; printf 'corrupt\n' > "$TEST_ROOT/etc/scut-multiwan/native.night-budget"
TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 75 "$BIN/campus-portal-login" phy0-sta0
! grep -qE '^LOGIN|^LOGOUT' "$TEST_ROOT/trace" || fail 'bad budget bypass'
pass 'corrupt budget record refuses any Portal mutation'
reset; TEST_CLOCK='07 00 00'; FORCE_SCAN=1; export TEST_CLOCK FORCE_SCAN
run_rc 0 "$BIN/native-watchdog-fixture"
grep -q native-best-fixture "$TEST_ROOT/trace" || fail 'morning force skipped'
unset FORCE_SCAN
pass '07:00 still dispatches forced complete comparison'
reset; run_rc 0 "$BIN/scut-calendar-update" 2026
LC_ALL=C awk -v year=2026 -v day=2026-10-10 -f "$LIB/calendar-check.awk" "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt" > "$TEST_ROOT/result"
[ "$(cat "$TEST_ROOT/result")" = W ] || fail 'updater lost make-up Saturday'
pass 'official search and HTML parsing install a complete holiday/workday cache'
reset; TEST_CAL_BAD_NOTICE=1; export TEST_CAL_BAD_NOTICE
cp "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt" "$TEST_ROOT/before"
run_rc 1 "$BIN/scut-calendar-update" 2026
cmp "$TEST_ROOT/before" "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt" || fail 'bad HTML replaced cache'
pass 'unrecognized official HTML retains last good cache'
reset; TEST_CAL_FETCH_FAIL=1; export TEST_CAL_FETCH_FAIL
cp "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt" "$TEST_ROOT/before"
run_rc 1 "$BIN/scut-calendar-update" 2026
cmp "$TEST_ROOT/before" "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt" || fail 'download failure replaced cache'
pass 'official fetch failure retains last good cache'
reset; run_rc 0 "$BIN/scut-calendar-update"
[ ! -e "$TEST_ROOT/etc/scut-multiwan/calendar-2027.txt" ] || fail 'invented next-year data'
pass 'missing next-year notice leaves current-year calendar usable'
reset; night
run_rc 76 "$BIN/scut-calendar-update" 2026; notrace updaternight
pass 'calendar updater never fetches during overnight period'
reset
sed 's/共7天/共8天/' "$TEST_ROOT/fixtures/annual-2026.html" > "$TEST_ROOT/wrong.html"
LC_ALL=C awk -v year=2026 -v source=https://www.gov.cn/zhengce/content/202511/content_7047090.htm -f "$LIB/calendar-parse.awk" "$TEST_ROOT/wrong.html" > "$TEST_ROOT/rejected"
[ "$?" = 1 ] && [ ! -s "$TEST_ROOT/rejected" ] || fail 'partial/inconsistent calendar accepted'
pass 'announced day-count mismatch rejects entire annual update'
reset
sed 's/1月1日（周四）至3日（周六）/2025年12月31日至2026年1月2日/' "$TEST_ROOT/fixtures/annual-2026.html" > "$TEST_ROOT/cross.html"
LC_ALL=C awk -v year=2026 -v source=https://www.gov.cn/zhengce/content/202511/content_7047090.htm -f "$LIB/calendar-parse.awk" "$TEST_ROOT/cross.html" > "$TEST_ROOT/cross-calendar" || fail 'cross-year notice rejected'
grep -q '^2025-12-31 H$' "$TEST_ROOT/cross-calendar" || fail 'cross-year date missing'
pass 'explicit cross-year leave range parses without calendar guessing'
reset
sed '/四、劳动节/d' "$TEST_ROOT/fixtures/annual-2026.html" > "$TEST_ROOT/incomplete.html"
LC_ALL=C awk -v year=2026 -v source=https://www.gov.cn/zhengce/content/202511/content_7047090.htm -f "$LIB/calendar-parse.awk" "$TEST_ROOT/incomplete.html" > "$TEST_ROOT/rejected"
[ "$?" = 1 ] && [ ! -s "$TEST_ROOT/rejected" ] || fail 'partial annual notice accepted'
pass 'missing holiday section rejects whole cache replacement'

reset; night
/bin/sh -c '. "$1"; mw_night_claim native' sh "$COMMON" > "$TEST_ROOT/last-output" 2>&1
[ "$?" = 75 ] || fail 'budget claim without real Portal FD lock'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.night-budget")" = 'none 0 0 0' ] || fail 'unlocked budget changed'
pass 'night budget cannot be claimed without the actual kernel Portal lock'
reset
/bin/sh -c '. "$1"; mw_portal_lock 0 || exit; touch "$2/control-ready"; while :; do :; done' sh "$COMMON" "$TEST_ROOT" & holder=$!
while [ ! -f "$TEST_ROOT/control-ready" ]; do /bin/sleep 1; done
run_rc 75 "$BIN/scut-night-control" quiet 2026-10-09
[ ! -e "$TEST_ROOT/etc/scut-multiwan/overnight.override" ] || fail 'override changed mid-transaction'
kill -9 "$holder"; wait "$holder" 2>/dev/null || true
rm "$TEST_ROOT/control-ready"
run_rc 0 "$BIN/scut-night-control" quiet 2026-10-09
pass 'manual policy override waits for Portal transaction completion'
