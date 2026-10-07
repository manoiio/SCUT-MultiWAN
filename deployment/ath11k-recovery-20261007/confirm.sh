#!/bin/sh
set -eu
B=/root/scut-ath11k-backup-20261007
exec 6>>"$B/guard.lock"
flock -n 6 || exit 75
test "$(cat "$B/state")" = testing
test "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$B/testing-boot")"
echo confirmed > "$B/state.new"
mv "$B/state.new" "$B/state"
p=$(cat "$B/guard.pid")
if test -r /proc/$p/stat && test "$(awk '{print $22}' /proc/$p/stat)" = "$(cat "$B/guard.start")" &&
   test "$(readlink /proc/$p/exe)" = /bin/busybox; then
    kill "$p"
fi
/etc/init.d/scut-ath11k-guard disable
sync
