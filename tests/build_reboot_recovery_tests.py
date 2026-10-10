"""Build isolated BusyBox tests for log retention and wired route convergence."""
from pathlib import Path
import tarfile
import re

root = Path(__file__).resolve().parents[1]
remote = '/tmp/scut-reboot-recovery-tests-20261010'
out = root / 'work/reboot-recovery-20261010/focused'
for directory in ('usr/bin', 'usr/lib/scut-multiwan', 'bin', 'etc/scut-logs',
                  'proc/sys/kernel/random', 'proc/123', 'sys/class/thermal/thermal_zone0'):
    (out / directory).mkdir(parents=True, exist_ok=True)
for name in ('scut-reboot-watch', 'scut-wired-route-recover'):
    source = (root / 'candidate/usr/bin' / name).read_text()
    source = re.sub(r'(?<![a-zA-Z0-9_/.])(?:/usr/lib/scut-multiwan|/usr/bin|/etc|/tmp|/proc|/sys)',
                    lambda match: remote + match[0], source)
    (out / 'usr/bin' / name).write_text(source)
(out / 'usr/lib/scut-multiwan/common.sh').write_text('''
mw_lock() { [ "${TEST_LOCK:-0}" = 0 ] || return 75; }
mw_require_route() { [ "${TEST_POLICY:-0}" = 0 ] || return 76; }
mw_uptime() { cat "$TEST_ROOT/clock"; }
''')
(out / 'bin/logger').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_ROOT/logger.trace"\n')
(out / 'bin/sync').write_text('#!/bin/sh\necho sync >> "$TEST_ROOT/sync.trace"\n')
(out / 'bin/sleep').write_text('''#!/bin/sh
now="$(cat "$TEST_ROOT/clock")"
echo "$((now+$1))" > "$TEST_ROOT/clock"
''')
(out / 'bin/ip').write_text('''#!/bin/sh
n="$(cat "$TEST_ROOT/calls" 2>/dev/null)"; n="${n:-0}"
[ "$n" -lt "${TEST_AFTER:-3}" ] || echo 'default via 10.1.1.1 dev wan'
''')
(out / 'usr/bin/dualwan-refresh').write_text('''#!/bin/sh
n="$(cat "$TEST_ROOT/calls" 2>/dev/null)"; n="${n:-0}"
echo "$((n+1))" > "$TEST_ROOT/calls"
[ "${TEST_CHANGED:-0}" = 0 ] || echo '999 456' > "$TEST_ROOT/tmp/scut-wired-ready"
[ "${TEST_BUSY_FIRST:-0}" = 0 ] || [ "$n" -gt 0 ] || exit 75
exit "${TEST_REFRESH_RC:-0}"
''')
(out / 'run.sh').write_text('''#!/bin/sh
set -eu
export TEST_ROOT=__ROOT__
export PATH="$TEST_ROOT/bin:$PATH"
cd "$TEST_ROOT"
count=0
check() { count=$((count+1)); "$@" || { echo "FAIL check=$count"; exit 1; }; }
watch="$TEST_ROOT/usr/bin/scut-reboot-watch"
route="$TEST_ROOT/usr/bin/scut-wired-route-recover"
mkdir -p tmp/scut-multiwan-locks
rm -f etc/scut-logs/* logger.trace sync.trace
echo aaaaaaaa > proc/sys/kernel/random/boot_id
echo '100.30 200.0' > proc/uptime
echo 'MemAvailable: 150000 kB' > proc/meminfo
echo '0.1 0.2 0.3 1/22 23' > proc/loadavg
echo 56000 > sys/class/thermal/thermal_zone0/temp
sh "$watch" archive
check test "$(cat etc/scut-logs/last.boot)" = aaaaaaaa
check test ! -f etc/scut-logs/previous-1.log
sh "$watch" archive
check test "$(wc -l < sync.trace)" = 1
echo critical-old > etc/scut-logs/system.log.old
echo critical-current > etc/scut-logs/system.log
echo bbbbbbbb > proc/sys/kernel/random/boot_id
sh "$watch" archive
check grep -q critical-old etc/scut-logs/previous-1.log
check grep -q critical-current etc/scut-logs/previous-1.log
check test "$(ls -l etc/scut-logs/previous-1.log | cut -c1-10)" = -rw-------
for id in cccccccc dddddddd eeeeeeee ffffffff; do
    echo "$id" > proc/sys/kernel/random/boot_id
    sh "$watch" archive
done
check test "$(ls etc/scut-logs/previous-*.log | wc -l)" = 4
check grep -q 'previous_boot=bbbbbbbb' etc/scut-logs/previous-4.log
before="$(sha256sum etc/scut-logs/previous-1.log)"
sh "$watch" archive
check test "$before" = "$(sha256sum etc/scut-logs/previous-1.log)"
dd if=/dev/zero of=etc/scut-logs/system.log bs=1024 count=600 2>/dev/null
cp etc/scut-logs/system.log etc/scut-logs/system.log.old
echo 11111111 > proc/sys/kernel/random/boot_id
sh "$watch" archive
check test "$(wc -c < etc/scut-logs/previous-1.log)" -lt 1048800
sh "$watch" once
check grep -q 'uptime=100 mem_available_kb=150000 load=0.1,0.2,0.3 temperature_mc=56000' logger.trace
reset_route() {
    echo 0 > clock; rm -f calls
    echo '123 456' > tmp/scut-wired-ready
    awk 'BEGIN {for(i=1;i<=21;i++) printf "0 "; print "456"}' > proc/123/stat
    ln -sf "$TEST_ROOT/usr/bin/scutclient-wired" proc/123/exe
    unset TEST_POLICY TEST_CHANGED TEST_BUSY_FIRST TEST_REFRESH_RC TEST_AFTER TEST_LOCK
}
reset_route
sh "$route" 123
check test "$(cat calls)" = 3
check test "$(cat clock)" = 30
reset_route; export TEST_BUSY_FIRST=1
sh "$route" 123
check test "$(cat calls)" = 3
reset_route; export TEST_POLICY=1
rc=0; sh "$route" 123 || rc=$?
check test "$rc" = 76
check test ! -f calls
reset_route; echo '999 456' > tmp/scut-wired-ready
rc=0; sh "$route" 123 || rc=$?
check test "$rc" = 75
check test ! -f calls
reset_route; export TEST_CHANGED=1
rc=0; sh "$route" 123 || rc=$?
check test "$rc" = 75
check test "$(cat calls)" = 1
reset_route; export TEST_REFRESH_RC=75 TEST_AFTER=999
rc=0; sh "$route" 123 || rc=$?
check test "$rc" = 75
check test "$(cat calls)" = 6
reset_route; export TEST_REFRESH_RC=1
rc=0; sh "$route" 123 || rc=$?
check test "$rc" = 1
check test "$(cat calls)" = 1
reset_route; export TEST_LOCK=1
rc=0; sh "$route" 123 || rc=$?
check test "$rc" = 75
check test ! -f calls
echo original-severity > etc/scut-logs/raw.log
echo original-older > etc/scut-logs/raw.log.old
echo normalized-view > etc/scut-logs/system.log
echo 22222222 > proc/sys/kernel/random/boot_id
sh "$watch" archive
check grep -q original-severity etc/scut-logs/previous-1.log
check grep -q original-older etc/scut-logs/previous-1.log
check sh -c '! grep -q normalized-view "$1"' sh etc/scut-logs/previous-1.log
echo "ALL $count REBOOT/ROUTE CHECKS PASSED (isolated; no authentication or production routes)"
'''.replace('__ROOT__', remote))
for path in out.rglob('*'):
    if path.is_file():
        path.chmod(0o700)
with tarfile.open(out.parent / 'focused-tests.tar', 'w') as bundle:
    for path in out.iterdir():
        bundle.add(path, arcname=path.name)
print('isolated reboot/route suite built')
