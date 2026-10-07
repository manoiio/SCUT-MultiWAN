from pathlib import Path
import shutil
import tarfile
import subprocess
import os
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--remote-root', default='/tmp/scut-multiwan-tests-experience-20261006')
args = parser.parse_args()
if not args.remote_root.startswith('/tmp/scut-multiwan-tests-') or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/_-' for c in args.remote_root):
    parser.error('remote root must be an isolated /tmp/scut-multiwan-tests-* path')
root = Path(__file__).resolve().parents[1]
out = root / 'tests/router-suite'
shutil.rmtree(out, ignore_errors=True)
(out/'bin').mkdir(parents=True)
remote = args.remote_root
for src in (root/'candidate').rglob('*'):
    if not src.is_file(): continue
    rel = src.relative_to(root/'candidate')
    dst = out/rel
    dst.parent.mkdir(parents=True,exist_ok=True)
    text = src.read_text()
    # Rewrite absolute paths once, so every write and command stays in isolation.
    prefixes = ['/usr/lib/scut-multiwan','/usr/bin','/etc','/tmp','/sys/class/net']
    mapping = {}
    for index, prefix in enumerate(prefixes):
        key = '__SCUT_PATH_' + str(index) + '__'
        mapping[key] = remote + ('/sys' if prefix=='/sys/class/net' else prefix)
        text = text.replace(prefix, key)
    for key,value in mapping.items(): text=text.replace(key,value)
    if rel.as_posix() == 'usr/bin/dualwan-refresh':
        # Only process-identity reads are redirected; inherited lock FDs stay real.
        text = text.replace('/proc/$WIRED_PID/stat', remote+'/proc/$WIRED_PID/stat')
    dst.write_text(text)
    dst.chmod(0o755)
# Public date fixtures; no downloaded HTML, network state or credentials.
shutil.copytree(root/'tests/fixtures', out/'fixtures')
portal_prefix = b'dr1003({"result":1,"message":"PRIVATE_FIXTURE_BODY","padding":"'
for name, size in [('portal-small.json', 1024), ('portal-boundary.json', 1048576), ('portal-over.json', 1048577)]:
    (out/'fixtures'/name).write_bytes(portal_prefix + b'x'*(size-len(portal_prefix)-4) + b'"});')
(out/'fixtures/portal-failure.json').write_bytes(b'dr1003({"result":0});')
calendar = subprocess.check_output(['awk', '-v', 'year=2026', '-v',
    'source=https://www.gov.cn/zhengce/content/202511/content_7047090.htm',
    '-f', str(root/'candidate/usr/lib/scut-multiwan/calendar-parse.awk'),
    str(root/'tests/fixtures/annual-2026.html')], env={**os.environ, 'LC_ALL':'C'})
(out/'fixtures/calendar-2026.txt').write_bytes(calendar)
# A separate watchdog fixture replaces ONLY native-best with a controlled failure.
wd=(out/'usr/bin/native-watchdog').read_text().replace(remote+'/usr/bin/native-best apply', remote+'/bin/native-best-fixture apply')
(out/'usr/bin/native-watchdog-fixture').write_text(wd)
(out/'usr/bin/native-watchdog-fixture').chmod(0o755)
mock = r'''#!/bin/sh
name="${0##*/}"
case "$name" in
 awk)
   # Historical fixtures subtract up to 900s. Preserve clock progression,
   # while allowing this isolated suite to run immediately after a reboot.
   if [ "$#" = 2 ] && [ "$2" = /proc/uptime ] && [ "$1" = '{print int($1)}' ]; then
     exec /usr/bin/awk '{print int($1)+10000}' "$2"
   fi
   exec /usr/bin/awk "$@";;
 date) case "$1" in '+%Y-%m-%d %u %H %M %S') echo "${TEST_DATE:-2026-10-08} ${TEST_WEEKDAY:-4} ${TEST_CLOCK:-20 00 00}";; '+%H %M %S') echo "${TEST_CLOCK:-20 00 00}";; +%s) echo "${TEST_EPOCH:-1791432000}";; -d) echo "$2";; *) echo 'test clock';; esac; exit 0;;
 sleep)
   if [ "$1" -ge 20 ] || { [ "${TEST_LEGACY:-0}" = 1 ] && [ "$1" = 2 ]; }; then /bin/sleep 1; fi
   exit 0;;
 logger) [ -z "${TEST_PORTAL_LOG_CAPTURE:-}" ] || printf '%s\n' "$*" >> "$TEST_ROOT/portal-log"; exit 0;;
 scutclient-wired)
   read -r fixture_user; read -r fixture_pass
   [ "$fixture_user" = test-user ] && [ "$fixture_pass" = test-password ] || exit 98
   echo "$$" > "$TEST_ROOT/mock-engine.pid"
   trap 'echo engine-stopped >> "$TEST_ROOT/trace"; exit 0' TERM INT
   while :; do /bin/sleep 1; done;;
 readlink)
   case "$1" in /proc/999999/exe) echo "$TEST_ROOT/usr/bin/scutclient-wired";; *) busybox readlink "$@";; esac; exit $?;;
 timeout) shift; exec "$@";;
 native-best-fixture) echo "native-best-fixture" >> "$TEST_ROOT/trace"; exit "${TEST_BEST_RC:-0}";;
 uci) echo "uci $*" >> "$TEST_ROOT/trace"; exit 0;;
 wifi) echo "wifi $*" >> "$TEST_ROOT/trace"; [ "$1" = up ] && touch "$TEST_ROOT/$2-enabled"; [ "$1" = down ] && rm -f "$TEST_ROOT/$2-enabled"; exit 0;;
 ifup) [ "${TEST_DHCP_RECOVERY:-0}" != 1 ] || touch "$TEST_ROOT/dhcp-restored"; echo "ifup $*" >> "$TEST_ROOT/trace"; exit 0;;
 ifdown|sysctl) echo "$name $*" >> "$TEST_ROOT/trace"; exit 0;;
 ping)
   echo "ping" >> "$TEST_ROOT/trace"
   count="$(cat "$TEST_ROOT/ping-count" 2>/dev/null)"; count="${count:-0}"; count=$((count+1)); echo "$count" > "$TEST_ROOT/ping-count"
   [ "${TEST_VERIFY_PING_FAIL:-0}" = 1 ] && [ "$count" -gt 5 ] && exit 1
   echo "64 bytes: time=1.0 ms"; exit "${TEST_PING_FAIL:-0}";;
 ubus|ifstatus)
   if [ "$name" = ubus ] && [ "$3" = control ]; then
     dev="${2#wpa_supplicant.}"
     echo "REASSOCIATE $dev" >> "$TEST_ROOT/trace"
     if [ "${TEST_REASSOC_FAIL:-0}" = 1 ]; then printf '{"result":"FAIL"}\n'; exit 0; fi
     [ "${TEST_REASSOC_STUCK:-0}" = 1 ] || touch "$TEST_ROOT/reassociated-$dev"
     [ "${TEST_REASSOC_IP_CHANGE:-0}" = 1 ] && touch "$TEST_ROOT/changed-ip-$dev"
     printf '{"result":"OK"}\n'; exit 0
   fi
   [ "$name" = ubus ] && iface="${2##*.}" || iface="$1"
   case "$iface" in wan1) dev=phy0-sta0; up=true;; wan2) dev=phy2-sta0; up=false; [ -f "$TEST_ROOT/radio2-enabled" ] && up=true;; usbwan) dev=phy3-sta0; up=true;; wan) dev=wan; up=true;; esac
   printf '{\n"up": %s,\n"l3_device": "%s"\n}\n' "$up" "$dev"; exit 0;;
 iw)
   [ "$1" = phy ] && { echo "iw-create $*" >> "$TEST_ROOT/trace"; exit 0; }
   [ "$#" = 1 ] && { printf 'phy#3\n Interface phy3-sta0\n type managed\nphy#0\n Interface phy0-sta0\n type managed\n'; exit 0; }
   dev="$2"; action="$3"
   case "$action" in
    link)
      case "$dev" in phy0-sta0) [ "${TEST_ACTIVE:-radio0}" = radio0 ] || exit 1;; phy2-sta0) [ "${TEST_ACTIVE:-radio0}" = both ] || [ -f "$TEST_ROOT/radio2-enabled" ] || exit 1;; esac
      printf 'Connected to 00:11:22:33:44:55 (on %s)\n freq: 5180\n' "$dev";;
    info)
      [ "$dev" = phy0-sta0 ] || [ "$dev" = phy3-sta0 ] || [ -f "$TEST_ROOT/radio2-enabled" ] || exit 1
      if [ "${TEST_LEGACY:-0}" = 1 ] && [ ! -f "$TEST_ROOT/reassociated-$dev" ]; then
        echo 'channel 36 (5180 MHz), width: 20 MHz (no HT)'
      else echo 'channel 36 (5180 MHz), width: 40 MHz'; fi;;
    station)
      dumps="$(cat "$TEST_ROOT/dump-count" 2>/dev/null)"; dumps="${dumps:-0}"; dumps=$((dumps+1)); echo "$dumps" > "$TEST_ROOT/dump-count"
      assoc=1000.0s; [ "${TEST_ASSOC_CHANGE:-999999}" -gt "$dumps" ] || assoc=1001.0s
      [ ! -f "$TEST_ROOT/reassociated-$dev" ] || assoc=1002.0s
      printf 'Station 00:11:22:33:44:55 (on %s)\n' "$dev"
      printf 'rx packets: %s\nassociated at [boottime]: %s\n' "$((900+dumps))" "$assoc"
      rx="${TEST_RX:-11}"; [ "${TEST_RX_VALID_LIMIT:-999999}" -ge "$dumps" ] || rx='?'
      [ "${TEST_CONNECTED:-1000}" = missing ] || printf 'connected time: %s seconds\n' "${TEST_CONNECTED:-1000}"
      printf 'tx packets: 10000\ntx failed: %s\nsignal avg: -39\ntx bitrate: 458.8 MBit/s HE-MCS %s\nrx bitrate: 573.5 MBit/s HE-MCS %s\n' "${TEST_FAILED:-0}" "${TEST_TX:-9}" "$rx";;
    scan)
      if [ "$4" = dump ]; then
        printf 'BSS %s(on %s)\n last seen: %s ms ago\n' "${TEST_CACHE_BSSID:-00:11:22:33:44:55}" "$dev" "${TEST_CACHE_AGE:-10}"
        [ "${TEST_CACHE_HT:-1}" = 0 ] || echo ' HT capabilities:'
        exit 0
      fi
      echo "SCAN $dev" >> "$TEST_ROOT/trace"; [ "${TEST_SCAN_EMPTY:-}" = "$dev" ] && exit 0; printf 'BSS 00:11:22:33:44:55\n freq: 5180\n signal: -39\n SSID: scut-student\n';;
    set)
      if [ "${TEST_RATE_DEFER_ONCE:-0}" = 1 ] && [ "$dev" = phy2-sta0 ] && [ ! -f "$TEST_ROOT/rate-deferred" ]; then touch "$TEST_ROOT/rate-deferred"; exit 75; fi
      echo "RATE $dev $*" >> "$TEST_ROOT/trace"; case "$*" in *2:7*) [ "${TEST_ROLLBACK_RATE_FAIL:-0}" = 1 ] && exit 1;; esac; exit "${TEST_RATE_FAIL:-0}";;
    *) echo "iw $*" >> "$TEST_ROOT/trace";;
   esac; exit $?;;
 ip)
   dev=; prev=
   for arg in "$@"; do [ "$prev" = dev ] && dev="$arg"; prev="$arg"; done
   case "$dev" in phy0-sta0) ip=10.1.1.10; net=10.1.1.0/24; gw=10.1.1.1;; phy2-sta0) ip=10.3.3.30; net=10.3.3.0/24; gw=10.3.3.1;; phy3-sta0) ip=10.2.2.20; net=10.2.2.0/24; gw=10.2.2.1;; wan) ip=10.4.4.40; net=10.4.4.0/24; gw=10.4.4.1;; esac
   [ ! -f "$TEST_ROOT/changed-ip-$dev" ] || ip=10.1.1.99
   case "$*" in
    '-4 -o addr show dev wan') echo "4: wan inet ${TEST_WIRED_IP:-10.4.4.40}/24 scope global";;
    *'addr show'*) echo "1: $dev inet $ip/24 scope global";;
    *'route show dev '*'scope link'*) echo "$net dev $dev scope link";;
    *'route show dev '*) echo "default via $gw dev $dev";;
    'rule show') [ -f "$TEST_ROOT/rule-removed" ] || printf '103:\tfrom all iif br-lan lookup 103\n';;
    'rule del pref 103') [ -f "$TEST_ROOT/rule-removed" ] && exit 1; touch "$TEST_ROOT/rule-removed"; echo "ip $*" >> "$TEST_ROOT/trace";;
    'rule add '*) rm -f "$TEST_ROOT/rule-removed"; echo "ip $*" >> "$TEST_ROOT/trace";;
    'route show table 103') printf 'default\n nexthop via 10.1.1.1 dev phy0-sta0 weight 1\n nexthop via 10.2.2.1 dev phy3-sta0 weight 1\n10.1.1.0/24 dev phy0-sta0 scope link\n10.2.2.0/24 dev phy3-sta0 scope link\n';;
    'route replace '*|'route flush '*|'route del '*) echo "ip $*" >> "$TEST_ROOT/trace"; case "$*" in *default*) [ "${TEST_ROUTE_FAIL:-0}" = 0 ] || exit 1;; esac;;
    'link '*) exit 0;;
    *) echo "ip $*" >> "$TEST_ROOT/trace";;
   esac; exit 0;;
 curl)
   dev=; target=; prev=; url=; pwarg=0; output=; resolved=0; cap=
   for arg in "$@"; do
     [ "$prev" = --interface ] && dev="$arg"
     [ "$prev" = --output ] && output="$arg"
     [ "$prev" = --resolve ] && resolved=1
     [ "$prev" = --max-filesize ] && cap="$arg"
     case "$arg" in
      http*://*) url="$arg";;
      wlan_user_ip=*) target="${arg#*=}";;
      user_password@/proc/self/fd/0) pwarg=1;;
      user_password=*) exit 98;;
     esac
     prev="$arg"
   done
   case "$url" in
    *'sousuo.www.gov.cn/search-gov/data')
      echo 'CAL_SEARCH' >> "$TEST_ROOT/trace"
      [ "${TEST_CAL_FETCH_FAIL:-0}" = 0 ] || exit 28
      cp "$TEST_ROOT/fixtures/search-2026.json" "$output"; exit 0;;
    *'www.gov.cn/zhengce/'*)
      echo 'CAL_DOWNLOAD' >> "$TEST_ROOT/trace"
      [ "${TEST_CAL_DOWNLOAD_FAIL:-0}" = 0 ] || exit 28
      if [ "${TEST_CAL_BAD_NOTICE:-0}" = 1 ]; then echo 'invalid annual notice' > "$output"
      else cp "$TEST_ROOT/fixtures/annual-2026.html" "$output"; fi
      printf '%s' "$url"; exit 0;;
    *neverssl*) printf '%s' "${TEST_REDIRECT-https://s.scut.edu.cn/a79.htm?wlanacip=10.0.0.1}";;
    *'/portal/mac/unbind')
      [ "${TEST_LOGOUT_DEVICE_FAIL:-}" != "$dev" ] || exit 7
      [ "$cap" = 1048576 ] || exit 98
      echo "LOGOUT $dev $target" >> "$TEST_ROOT/trace"
      if [ -n "${TEST_PORTAL_LOGOUT_BODY:-}" ]; then
        head -c "$cap" "$TEST_PORTAL_LOGOUT_BODY"
        [ "$(wc -c < "$TEST_PORTAL_LOGOUT_BODY")" -le "$cap" ] || exit 63
        exit "${TEST_PORTAL_LOGOUT_RC:-0}"
      fi
      if [ "$target" = "${TEST_FAIL_LOGOUT_IP:-never}" ]; then echo '{"result":0}'; else
        case "$target" in 167837962) touch "$TEST_ROOT/phy0-sta0-offline"; rm -f "$TEST_ROOT/phy0-sta0-login";; 167969566) touch "$TEST_ROOT/phy2-sta0-offline"; rm -f "$TEST_ROOT/phy2-sta0-login";; 167903764) touch "$TEST_ROOT/phy3-sta0-offline"; rm -f "$TEST_ROOT/phy3-sta0-login";; esac
        echo '{"result":1}'
      fi;;
    *'/portal/login')
      [ "$cap" = 1048576 ] || exit 98
      [ "$pwarg" = 1 ] || exit 98
      password="$(cat)"; [ "$password" = 'test-password' ] || exit 98
      case "$dev" in phy3-sta0) slot=usb;; *) slot=native;; esac
      read -r recorded owner < "$TEST_ROOT/etc/scut-multiwan/$slot.session"
      [ "$recorded" = "$target" ] && [ "$owner" = "$dev" ] || exit 97
      echo "LOGIN $dev $target" >> "$TEST_ROOT/trace"
      touch "$TEST_ROOT/$dev-login"
      [ "${TEST_LOGIN_TIMEOUT:-0}" = 1 ] && exit 28
      if [ -n "${TEST_PORTAL_LOGIN_BODY:-}" ]; then
        head -c "$cap" "$TEST_PORTAL_LOGIN_BODY"
        [ "$(wc -c < "$TEST_PORTAL_LOGIN_BODY")" -le "$cap" ] || exit 63
        exit "${TEST_PORTAL_LOGIN_RC:-0}"
      fi
      echo '{"result":1}';;
    *bilibili*|*jd.com*)
      if [ "${TEST_DNS_FAIL:-0}" = 1 ] && [ "$resolved" = 0 ]; then echo DNS_FAILURE >> "$TEST_ROOT/trace"; printf 000; exit 6; fi
      [ "$resolved" = 0 ] || echo CACHED_TLS >> "$TEST_ROOT/trace"
      case "$url" in *bilibili*) [ "${TEST_PRIMARY_FAIL:-0}" = 0 ] || { printf 000; exit 28; };; esac
      echo "HTTPS $dev" >> "$TEST_ROOT/trace"
      case "$dev" in
        phy0-sta0) online="${TEST_NATIVE_ONLINE:-1}";;
        phy2-sta0) online="${TEST_CANDIDATE_ONLINE:-0}";;
        phy3-sta0) online="${TEST_USB_ONLINE:-1}";;
        wan) online="${TEST_WIRED_ONLINE:-0}";;
      esac
      [ -f "$TEST_ROOT/dhcp-restored" ] && [ "$dev" = phy0-sta0 ] && online=1
      [ -f "$TEST_ROOT/$dev-offline" ] && online=0
      [ -f "$TEST_ROOT/$dev-login" ] && online="${TEST_AFTER_LOGIN_ONLINE:-1}"
      [ "$online" = 1 ] || { printf 000; exit 28; }
      printf '%s %s' "${TEST_HTTPS_CODE:-200}" '198.51.100.20';;
    *) exit 1;;
   esac; exit 0;;
esac
exit 1
'''
(out/'bin/mock').write_text(mock)
(out/'bin/mock').chmod(0o755)
for name in ['awk','date','sleep','logger','readlink','scutclient-wired','timeout','native-best-fixture','uci','wifi','ifup','ifdown','sysctl','ping','ubus','ifstatus','iw','ip','curl']:
    (out/'bin'/name).symlink_to('mock')
(out/'usr/bin/scutclient-wired').symlink_to('../../bin/mock')
runner=r'''#!/bin/sh
set -u
TEST_ROOT=/tmp/scut-multiwan-tests
export TEST_ROOT
PATH="$TEST_ROOT/bin:$PATH"
export PATH
BIN="$TEST_ROOT/usr/bin"
COMMON="$TEST_ROOT/usr/lib/scut-multiwan/common.sh"
N=0
reset() {
 unset TEST_RATE_DEFER_ONCE TEST_LOGOUT_DEVICE_FAIL TEST_DHCP_RECOVERY
 rm -f "$TEST_ROOT/rate-deferred" "$TEST_ROOT/dhcp-restored" "$TEST_ROOT/tmp/native-watchdog"/dhcp.*
 unset TEST_LEGACY TEST_REASSOC_FAIL TEST_REASSOC_STUCK TEST_REASSOC_IP_CHANGE TEST_CACHE_AGE TEST_CACHE_HT TEST_CACHE_BSSID
 rm -rf "$TEST_ROOT/tmp/scut-link-recover"
 rm -f "$TEST_ROOT"/reassociated-* "$TEST_ROOT"/changed-ip-* "$TEST_ROOT/tmp/qca-fixed-rate"/*.legacy
 unset TEST_PORTAL_LOGIN_BODY TEST_PORTAL_LOGOUT_BODY TEST_PORTAL_LOGIN_RC TEST_PORTAL_LOGOUT_RC TEST_PORTAL_LOG_CAPTURE
 rm -f "$TEST_ROOT/portal-log"
 unset TEST_WIRED_ONLINE TEST_WIRED_IP TEST_RX_VALID_LIMIT TEST_ASSOC_CHANGE TEST_DNS_FAIL
 rm -f "$TEST_ROOT/etc/scut-wired.conf" "$TEST_ROOT/etc/scut-multiwan/wired.session" "$TEST_ROOT/etc/scut-multiwan/wired.night-budget"
 unset TEST_CONNECTED TEST_DATE TEST_WEEKDAY TEST_EPOCH TEST_PRIMARY_FAIL TEST_CAL_FETCH_FAIL TEST_CAL_DOWNLOAD_FAIL TEST_CAL_BAD_NOTICE TEST_CLOCK TEST_REDIRECT TEST_HTTPS_CODE TEST_ACTIVE TEST_BEST_RC TEST_NATIVE_ONLINE TEST_USB_ONLINE TEST_CANDIDATE_ONLINE TEST_AFTER_LOGIN_ONLINE TEST_FAIL_LOGOUT_IP TEST_LOGIN_TIMEOUT TEST_ROUTE_FAIL TEST_PING_FAIL TEST_TX TEST_RX TEST_FAILED TEST_RATE_FAIL TEST_VERIFY_PING_FAIL TEST_ROLLBACK_RATE_FAIL TEST_SCAN_EMPTY
 : > "$TEST_ROOT/trace"
 rm -f "$TEST_ROOT/dump-count"
 rm -rf "$TEST_ROOT/tmp/scut-multiwan-health"
 rm -f "$TEST_ROOT/tmp/native-watchdog/retry_scan" "$TEST_ROOT/tmp/native-watchdog/scan_failures"
 rm -f "$TEST_ROOT/ping-count"
 rm -f "$TEST_ROOT/phy0-sta0-offline" "$TEST_ROOT/phy2-sta0-offline" "$TEST_ROOT/phy3-sta0-offline"
 rm -f "$TEST_ROOT/radio2-enabled" "$TEST_ROOT/radio0-enabled" "$TEST_ROOT/rule-removed" "$TEST_ROOT/phy0-sta0-login" "$TEST_ROOT/phy2-sta0-login" "$TEST_ROOT/phy3-sta0-login"
 mkdir -p "$TEST_ROOT/etc/scut-multiwan" "$TEST_ROOT/tmp/native-watchdog" "$TEST_ROOT/sys/phy0-sta0" "$TEST_ROOT/sys/phy2-sta0" "$TEST_ROOT/sys/phy3-sta0"
 cp "$TEST_ROOT/fixtures/calendar-2026.txt" "$TEST_ROOT/etc/scut-multiwan/calendar-2026.txt"
 rm -f "$TEST_ROOT/etc/scut-multiwan/overnight.override" "$TEST_ROOT/etc/scut-multiwan/calendar-2027.txt"
 printf 'none 0 0 0\n' > "$TEST_ROOT/etc/scut-multiwan/native.night-budget"
 printf 'none 0 0 0\n' > "$TEST_ROOT/etc/scut-multiwan/usb.night-budget"
 printf '10.1.1.10 phy0-sta0\n' > "$TEST_ROOT/etc/scut-multiwan/native.session"
 printf '10.2.2.20 phy3-sta0\n' > "$TEST_ROOT/etc/scut-multiwan/usb.session"
 rm -f "$TEST_ROOT/tmp/native-watchdog/last_scan"
 rm -f "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
 cat > "$TEST_ROOT/etc/campus-portal.conf" <<CONF
NATIVE_USER=test-user
NATIVE_PASS=test-password
USB_USER=test-user
USB_PASS=test-password
CONF
}
fail() { echo "FAIL: $*"; cat "$TEST_ROOT/trace"; exit 1; }
pass() { N=$((N+1)); echo "PASS $N: $*"; }
run_rc() { expected="$1"; shift; "$@" > "$TEST_ROOT/last-output" 2>&1; actual=$?; [ "$actual" -eq "$expected" ] || { cat "$TEST_ROOT/last-output"; fail "rc=$actual expected=$expected $*"; }; }
notrace() { [ ! -s "$TEST_ROOT/trace" ] || fail "$* touched data plane"; }

for time in '00 06 00' '01 00 00' '06 59 59'; do
 for script in 'native-best apply' 'native-best switch radio2' 'qca-radio-survey' 'native-watchdog' 'usb-watchdog' 'dualwan-refresh apply' 'fix-qca-sta-rate phy0-sta0' 'campus-portal-login phy0-sta0' 'campus-usb-login phy3-sta0' 'campus-portal-logout phy0-sta0' 'campus-usb-logout phy3-sta0' 'campus-portal-login.impl phy0-sta0'; do
  reset; TEST_CLOCK="$time"; export TEST_CLOCK
  set -- $script
  "$BIN/$1" ${2-} ${3-} > "$TEST_ROOT/last-output" 2>&1
  rc=$?; [ "$rc" = 76 ] || [ "$rc" = 0 ] || fail "quiet rc=$rc $script"
  notrace "$script $time"
 done
 pass "all mutation entry points silent at $time"
done
reset; TEST_CLOCK='00 05 59'; export TEST_CLOCK
/bin/sh -c '. "$1"; mw_quiet_now; [ "$?" = 1 ] && [ "$MW_SECONDS" = 359 ]' sh "$COMMON" || fail 'quiet started early'
pass '00:05:59 outside quiet window (operation margins still apply)'
reset; TEST_CLOCK='00 05 50'; export TEST_CLOCK; run_rc 76 "$BIN/dualwan-refresh" apply; notrace boundary; pass 'pre-boundary operation margin'
for time in '07 00 00' '07 29 59'; do
 reset; TEST_CLOCK="$time"; export TEST_CLOCK
 run_rc 0 "$BIN/campus-portal-login" phy0-sta0
 grep -q '^HTTPS ' "$TEST_ROOT/trace" || fail 'resume skipped HTTPS'
 pass "active after new end at $time"
done
reset; run_rc 0 "$BIN/native-best" status; notrace status; pass 'native-best status is read-only'
reset; run_rc 0 "$BIN/fix-qca-sta-rate" phy3-sta0; notrace USB; pass 'QCA helper refuses phy3'
reset; TEST_HTTPS_CODE=302; TEST_REDIRECT='https://elsewhere.invalid/?wlanacip=10.0.0.1'; export TEST_HTTPS_CODE TEST_REDIRECT
run_rc 1 "$BIN/campus-portal-login" phy0-sta0; ! grep -qE 'LOGIN|LOGOUT' "$TEST_ROOT/trace" || fail 'false redirect login'; pass 'HTTPS redirect and wrong Portal host do not authorize login'
reset; TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 0 "$BIN/campus-portal-login" phy0-sta0
[ "$(grep -E 'LOGIN|LOGOUT' "$TEST_ROOT/trace" | head -1)" = 'LOGOUT phy0-sta0 167837962' ] || fail 'release before login'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.1.1.10 phy0-sta0' ] || fail 'ledger'
pass 'confirmed release before login; password on stdin; journal before request'
reset; TEST_NATIVE_ONLINE=0; TEST_FAIL_LOGOUT_IP=167837962; export TEST_NATIVE_ONLINE TEST_FAIL_LOGOUT_IP
run_rc 1 "$BIN/campus-portal-login" phy0-sta0; ! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'login after failed release'; pass 'failed release blocks login'
reset; TEST_NATIVE_ONLINE=0; TEST_LOGIN_TIMEOUT=1; export TEST_NATIVE_ONLINE TEST_LOGIN_TIMEOUT
run_rc 1 "$BIN/campus-portal-login" phy0-sta0
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.1.1.10 phy0-sta0' ] || fail 'lost unknown session'
TEST_LOGIN_TIMEOUT=0; export TEST_LOGIN_TIMEOUT; rm -f "$TEST_ROOT/phy0-sta0-login"; : > "$TEST_ROOT/trace"
 rm -f "$TEST_ROOT/dump-count"
 rm -rf "$TEST_ROOT/tmp/scut-multiwan-health"
 rm -f "$TEST_ROOT/tmp/native-watchdog/retry_scan" "$TEST_ROOT/tmp/native-watchdog/scan_failures"
run_rc 0 "$BIN/campus-portal-login" phy0-sta0
[ "$(grep -E 'LOGIN|LOGOUT' "$TEST_ROOT/trace" | head -1)" = 'LOGOUT phy0-sta0 167837962' ] || fail 'blind retry'
pass 'ambiguous login retains journal and is released before retry'
reset; TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE; rm "$TEST_ROOT/etc/scut-multiwan/native.session"
run_rc 75 "$BIN/campus-portal-login" phy0-sta0; ! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'missing journal'; pass 'missing journal fails closed'
reset; printf '10.9.9.9 phy2-sta0\n' > "$TEST_ROOT/etc/scut-multiwan/native.session"; TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 0 "$BIN/campus-portal-login" phy0-sta0; grep -q 'LOGOUT phy0-sta0 168364297' "$TEST_ROOT/trace" || fail 'stale DHCP target'; pass 'surviving interface releases recorded old DHCP address'
reset; run_rc 0 "$BIN/native-best" switch radio2
order="$(grep -E 'LOGIN|LOGOUT' "$TEST_ROOT/trace")"
[ "$(printf '%s\n' "$order" | head -1)" = 'LOGOUT phy0-sta0 167837962' ] || fail 'switch order'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.3.3.30 phy2-sta0' ] || fail 'switch ledger'
pass 'Native switch is serialized, old release precedes new login'
reset; TEST_FAIL_LOGOUT_IP=167837962; export TEST_FAIL_LOGOUT_IP
run_rc 1 "$BIN/native-best" switch radio2; ! grep -q '^LOGIN' "$TEST_ROOT/trace" || fail 'unsafe switch'; pass 'Native switch aborts on old release failure'
reset; TEST_AFTER_LOGIN_ONLINE=0; export TEST_AFTER_LOGIN_ONLINE
run_rc 1 "$BIN/native-best" switch radio2
order="$(grep -E 'LOGIN|LOGOUT' "$TEST_ROOT/trace" | tr '\n' '|')"
case "$order" in *'LOGIN phy2-sta0 10.3.3.30|LOGOUT phy0-sta0 167969566|LOGIN phy0-sta0 10.1.1.10|'*) ;; *) fail "rollback order $order";; esac
pass 'failed candidate Internet verification releases candidate before old login'
reset; TEST_AFTER_LOGIN_ONLINE=0; TEST_FAIL_LOGOUT_IP=167969566; export TEST_AFTER_LOGIN_ONLINE TEST_FAIL_LOGOUT_IP
run_rc 1 "$BIN/native-best" switch radio2
! grep -q '^LOGIN phy0-sta0' "$TEST_ROOT/trace" || fail 'unsafe rollback'; pass 'uncertain candidate release blocks rollback login'
reset; TEST_ACTIVE=none; TEST_BEST_RC=23; export TEST_ACTIVE TEST_BEST_RC
run_rc 23 "$BIN/native-watchdog-fixture"; [ ! -f "$TEST_ROOT/tmp/native-watchdog/last_scan" ] || fail 'failed scan marked'; pass 'watchdog preserves failure and does not postpone retry'
reset; TEST_ACTIVE=none; export TEST_ACTIVE
run_rc 0 "$BIN/native-watchdog-fixture"; [ -s "$TEST_ROOT/tmp/native-watchdog/last_scan" ] || fail 'success not marked'; pass 'successful scan records monotonic timestamp'
reset; run_rc 0 "$BIN/dualwan-refresh" apply
! grep -qE 'rule del|route flush' "$TEST_ROOT/trace" || fail 'healthy refresh removed policy'
grep -q 'weight 1 nexthop via.*weight 1' "$TEST_ROOT/trace" || fail 'ECMP'; pass 'healthy ECMP refresh does not flush routes or remove valid rule'
reset; TEST_ROUTE_FAIL=1; export TEST_ROUTE_FAIL
run_rc 1 "$BIN/dualwan-refresh" apply; grep -q 'route flush table 103' "$TEST_ROOT/trace" || fail 'failed route left blackhole'; pass 'failed ECMP installation removes policy'
reset; TEST_NATIVE_ONLINE=0; export TEST_NATIVE_ONLINE
run_rc 0 "$BIN/dualwan-refresh" apply; grep -q 'default via 10.2.2.1 dev phy3-sta0' "$TEST_ROOT/trace" || fail 'USB fallback'; pass 'USB-only fallback'
reset; TEST_USB_ONLINE=0; export TEST_USB_ONLINE
run_rc 0 "$BIN/dualwan-refresh" apply; grep -q 'default via 10.1.1.1 dev phy0-sta0' "$TEST_ROOT/trace" || fail 'Native fallback'; pass 'Native-only fallback'
reset; TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0; export TEST_NATIVE_ONLINE TEST_USB_ONLINE
run_rc 1 "$BIN/dualwan-refresh" apply; grep -q 'route flush table 103' "$TEST_ROOT/trace" || fail 'both down blackhole'; pass 'both unhealthy removes policy'
reset; TEST_TX=11; export TEST_TX
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q 'he-mcs-5 2:11' "$TEST_ROOT/trace" || fail 'QCA MCS11 permitted'
grep -q 'he-mcs-5 2:9' "$TEST_ROOT/trace" || fail 'QCA precap'
pass 'QCA TX above 9 is capped at 9'
reset; TEST_RX=7; export TEST_RX
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'single low RX round downgraded'
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'RX downgrade'; pass 'two fresh low RX rounds downgrade QCA to MCS7'
reset; TEST_TX=7; export TEST_TX; mkdir -p "$TEST_ROOT/tmp/qca-fixed-rate"; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n7\n9000\n0\n%s\n%s\n1000.0s\n0\n0\n' "$((now-600))" "$((now-600))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q 'he-mcs-5 2:9' "$TEST_ROOT/trace" || fail 'stale promotion'; pass 'overnight sampling gap resets QCA promotion timer'
reset; TEST_TX=7; export TEST_TX; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n7\n9000\n0\n%s\n%s\n1000.0s\n0\n0\n' "$((now-301))" "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
grep -q 'he-mcs-5 2:9' "$TEST_ROOT/trace" || fail 'no valid promotion'; pass 'five-minute good candidate promotes and verifies MCS9'
reset; TEST_TX=7; TEST_VERIFY_PING_FAIL=1; export TEST_TX TEST_VERIFY_PING_FAIL; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n7\n9000\n0\n%s\n%s\n1000.0s\n0\n0\n' "$((now-301))" "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
[ "$(sed -n '2p' "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state")" = 7 ] || fail 'failed promotion retained'; pass 'failed MCS9 validation returns to MCS7'
reset; TEST_TX=7; TEST_VERIFY_PING_FAIL=1; TEST_ROLLBACK_RATE_FAIL=1; export TEST_TX TEST_VERIFY_PING_FAIL TEST_ROLLBACK_RATE_FAIL; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n7\n9000\n0\n%s\n%s\n1000.0s\n0\n0\n' "$((now-301))" "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 1 "$BIN/fix-qca-sta-rate" phy0-sta0; pass 'failed rate rollback reports failure'
reset; TEST_TX=7; export TEST_TX; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n7\n20000\n0\n%s\n%s\n1000.0s\n0\n0\n' "$((now-301))" "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q 'he-mcs-5 2:9' "$TEST_ROOT/trace" || fail 'counter-reset promotion'; pass 'same-BSSID counter reset cancels promotion timer'
reset; TEST_FAILED=30; export TEST_FAILED; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n9\n10000\n0\n0\n%s\n1000.0s\n0\n0\n' "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'failures with no successful packets'; pass 'TX failure burst downgrades even with zero successful packets'
# RX initialization grace is bounded by real driver association age.
for age in 0 10 14; do
 reset; TEST_RX=0; TEST_CONNECTED="$age"; export TEST_RX TEST_CONNECTED
 run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
 ! grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'warmup false downgrade'
 pass "RX zero at association age $age keeps MCS9"
done
for age in 15 missing invalid; do
 reset; TEST_RX=0; TEST_CONNECTED="$age"; export TEST_RX TEST_CONNECTED
 run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
 run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
 grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'unbounded warmup'
 pass "RX zero at age $age retains conservative downgrade"
done
reset; TEST_RX=0; TEST_CONNECTED=0; TEST_PING_FAIL=1; export TEST_RX TEST_CONNECTED TEST_PING_FAIL
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'warmup hid gateway failure'; pass 'warmup still downgrades for gateway loss'
reset; TEST_CONNECTED=0; TEST_FAILED=30; export TEST_CONNECTED TEST_FAILED; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n9\n10000\n0\n0\n%s\n1000.0s\n0\n0\n' "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'warmup hid TX failures'; pass 'warmup still downgrades for TX failure burst'
reset; TEST_CONNECTED=10; TEST_TX=7; export TEST_CONNECTED TEST_TX; now="$(awk '{print int($1)}' /proc/uptime)"
printf '00:11:22:33:44:55@5180\n7\n9000\n0\n%s\n%s\n1000.0s\n0\n0\n' "$((now-301))" "$((now-1))" > "$TEST_ROOT/tmp/qca-fixed-rate/phy0-sta0.state"
run_rc 0 "$BIN/fix-qca-sta-rate" phy0-sta0
! grep -q 'he-mcs-5 2:9' "$TEST_ROOT/trace" || fail 'warmup inherited promotion'; pass 'same-BSSID warmup cannot inherit promotion timer'
reset; TEST_CONNECTED=0; TEST_RX=0; TEST_ACTIVE=both; export TEST_CONNECTED TEST_RX TEST_ACTIVE; touch "$TEST_ROOT/radio2-enabled"
run_rc 0 "$BIN/fix-qca-sta-rate" phy2-sta0
! grep -q 'he-mcs-5 2:7' "$TEST_ROOT/trace" || fail 'radio2 warmup'; pass 'radio2 warmup protects RX initialization'
reset; TEST_USB_ONLINE=0; export TEST_USB_ONLINE; printf '10.8.8.8 phy3-sta0\n' > "$TEST_ROOT/etc/scut-multiwan/usb.session"
run_rc 0 "$BIN/campus-usb-login" phy3-sta0
grep -q '^LOGOUT phy3-sta0 168298504' "$TEST_ROOT/trace" || fail 'USB stale lease'; pass 'USB DHCP replacement releases old session before login'
reset; TEST_NATIVE_ONLINE=0; TEST_ROUTE_FAIL=1; export TEST_NATIVE_ONLINE TEST_ROUTE_FAIL
run_rc 1 "$BIN/dualwan-refresh" apply; grep -q 'route flush table 103' "$TEST_ROOT/trace" || fail 'single route error ignored'; pass 'single-WAN route installation failure is checked'
reset; TEST_SCAN_EMPTY=phy0-sta0; export TEST_SCAN_EMPTY
run_rc 0 "$BIN/native-best" survey
grep -q 'radio2: -39' "$TEST_ROOT/last-output" || fail 'one radio failure blocked other survey'; pass 'one empty radio scan still surveys the other'
reset
/bin/sh -c '. "$1"; sleep() { /bin/sleep "$1"; }; mw_run_bounded 1 /bin/sh -c '\''trap "" TERM; while :; do :; done'\''' sh "$COMMON" > "$TEST_ROOT/last-output" 2>&1
[ "$?" = 137 ] || fail 'bounded child was not killed'
pass 'scan deadline terminates a TERM-ignoring child in BusyBox ash'
reset
/bin/sh -c '. "$1"; mw_portal_lock 0 || exit; "$2" phy0-sta0' sh "$COMMON" "$BIN/campus-portal-login" > "$TEST_ROOT/last-output" 2>&1 || fail 'nested lock deadlock'
pass 'nested Portal wrapper reuses inherited kernel lock'
reset
/bin/sh -c '. "$1"; mw_lock native-best 8 || exit; touch "$2/ready"; while :; do :; done' sh "$COMMON" "$TEST_ROOT" & holder=$!
while [ ! -f "$TEST_ROOT/ready" ]; do /bin/sleep 1; done
run_rc 75 "$BIN/native-best" apply
run_rc 75 "$BIN/native-best" apply
kill -9 "$holder"; wait "$holder" 2>/dev/null || true
/bin/sh -c '. "$1"; mw_lock native-best 8' sh "$COMMON" || fail 'kernel lock stale after kill'
rm "$TEST_ROOT/ready"
pass 'concurrent losers cannot remove winner lock; SIGKILL releases it'
echo "ALL $N GROUPS PASSED"
'''
runner=runner.replace('echo "ALL $N GROUPS PASSED"', (root/'tests/holiday-cases.sh').read_text() + '\n' + (root/'tests/wired-cases.sh').read_text() + '\n' + (root/'tests/experience-cases.sh').read_text() + '\n' + (root/'tests/portal-response-cases.sh').read_text() + '\n' + (root/'tests/legacy-cases.sh').read_text() + '\n' + (root/'tests/recovery-cases.sh').read_text() + '\necho "ALL $N GROUPS PASSED"')
runner=runner.replace('/tmp/scut-multiwan-tests', remote)
(out/'run.sh').write_text(runner)
(out/'run.sh').chmod(0o755)
with tarfile.open(root/'tests/router-suite.tar','w') as tar:
    for path in out.iterdir(): tar.add(path,arcname=path.name)
print('isolated BusyBox suite built')
