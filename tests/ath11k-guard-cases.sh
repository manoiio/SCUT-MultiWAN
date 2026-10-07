#!/bin/sh
# Actual BusyBox test, with module paths, boot ID and reboot fully isolated.
set -eu
T=/tmp/scut-ath11k-guard-tests-20261007
S=/tmp/scut-ath11k-stage-20261007
test ! -e "$T"
mkdir -m700 "$T" "$T/backup" "$T/modules"
B=$T/backup
cp /root/scut-ath11k-backup-20261007/ath11k*.ko "$B/"
echo fixture-boot > "$T/boot"
: > "$T/reboots"
printf '#!/bin/sh\necho "$1" >> %s/init-calls\n' "$T" > "$T/init"
chmod 700 "$T/init"
for f in boot-guard rollback.sh timeout.sh confirm.sh; do
    sed -e "s@/root/scut-ath11k-backup-20261007@$B@g" \
        -e "s@/lib/modules/6.12.94@$T/modules@g" \
        -e "s@/proc/sys/kernel/random/boot_id@$T/boot@g" \
        -e "s@/etc/init.d/scut-ath11k-guard@$T/init@g" \
        -e "s@/sbin/reboot@echo reboot >> $T/reboots@g" \
        -e 's/^sync$/:/' "$S/$f" > "$B/$f"
done
sed 's/sleep 180/sleep 20/' "$B/timeout.sh" > "$B/timeout-long.sh"
sed 's/sleep 180/sleep 0/' "$B/timeout.sh" > "$B/timeout-now.sh"
cp "$B/timeout-long.sh" "$B/timeout.sh"
for m in ath11k.ko ath11k_ahb.ko; do cp "$B/$m" "$T/modules/$m"; done
sha256sum "$T/modules/ath11k.ko" "$T/modules/ath11k_ahb.ko" > "$B/modules-before.sha256"
boot_guard() { ( . "$B/boot-guard"; boot ); }
corrupt_targets() { echo candidate > "$T/modules/ath11k.ko"; echo candidate > "$T/modules/ath11k_ahb.ko"; }
boot_guard
test ! -e "$B/state"
echo 'PASS absent state'
echo allowed > "$B/state"
boot_guard
test "$(cat "$B/state")" = testing
cmp "$T/boot" "$B/testing-boot"
sh "$B/confirm.sh"
test "$(cat "$B/state")" = confirmed
echo 'PASS allowed boot and guarded confirmation'
sh "$B/timeout-now.sh"
test ! -s "$T/reboots"
echo 'PASS confirmed boot never reboots'
echo testing > "$B/state"
echo other-boot > "$B/testing-boot"
corrupt_targets
sh "$B/timeout-now.sh"
test "$(cat "$B/state")" = testing
test ! -s "$T/reboots"
echo 'PASS different boot never restores or reboots'
cp "$T/boot" "$B/testing-boot"
exec 5>>"$B/guard.lock"
flock -n 5
rc=0
sh "$B/timeout-now.sh" || rc=$?
test "$rc" = 75
test "$(cat "$B/state")" = testing
exec 5>&-
echo 'PASS competing guard lock blocks timeout'
sh "$B/timeout-now.sh"
test "$(cat "$B/state")" = rolled-back
sha256sum -c "$B/modules-before.sha256"
test "$(wc -l < "$T/reboots")" -eq 1
echo 'PASS unconfirmed timeout restores exact modules and requests one reboot'
echo testing > "$B/state"
corrupt_targets
boot_guard
test "$(cat "$B/state")" = rolled-back
sha256sum -c "$B/modules-before.sha256"
test "$(wc -l < "$T/reboots")" -eq 1
echo 'PASS second unconfirmed boot restores before loader without reboot'
corrupt_targets
echo wrong > "$B/ath11k.ko"
echo testing > "$B/state"
rc=0
sh "$B/timeout-now.sh" || rc=$?
test "$rc" != 0
test "$(cat "$B/state")" = testing
test "$(cat "$T/modules/ath11k.ko")" = candidate
test "$(wc -l < "$T/reboots")" -eq 1
echo 'PASS corrupted backup fails closed'
echo '8 isolated boot-guard groups passed'
