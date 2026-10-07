#!/bin/sh
set -eu
B=/root/scut-ath11k-backup-20261007
sleep 180
exec 6>>"$B/guard.lock"
flock -n 6 || exit 75
test "$(cat "$B/state")" = testing || exit 0
test "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$B/testing-boot")" || exit 0
sh "$B/rollback.sh"
sync
# Only the specifically authorized unconfirmed test boot can reach here.
/sbin/reboot
