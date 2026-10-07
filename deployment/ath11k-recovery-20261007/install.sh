#!/bin/sh
# This installer only stages the modules for an explicitly approved test boot.
set -eu
B=/root/scut-ath11k-backup-20261007
S=/tmp/scut-ath11k-stage-20261007
K=/lib/modules/6.12.94
test "$(uname -r)" = 6.12.94
test ! -e /etc/init.d/scut-ath11k-guard
test ! -e "$B/state"
sha256sum -c "$B/modules-before.sha256"
sha256sum -c "$B/preserved.sha256"
test "$(wc -c < "$S/ath11k.ko")" -eq 767360
test "$(wc -c < "$S/ath11k_ahb.ko")" -eq 29152
echo '3795196ca5c47c560ca16a20bc0a2b056319afdbf47b5c95978a2efc3989c6cd  /tmp/scut-ath11k-stage-20261007/ath11k.ko' | sha256sum -c -
echo '585b3d0a6de4c3666683b280f5dd9702e86b56026460e9e7ad70c913abbd82ba  /tmp/scut-ath11k-stage-20261007/ath11k_ahb.ko' | sha256sum -c -
for m in ath11k ath11k_ahb; do
    strings "$S/$m.ko" | grep -qx 'vermagic=6.12.94 SMP mod_unload aarch64'
done
for f in boot-guard rollback.sh timeout.sh confirm.sh; do sh -n "$S/$f"; done
cp "$S/rollback.sh" "$B/rollback.sh"
cp "$S/timeout.sh" "$B/timeout.sh"
cp "$S/confirm.sh" "$B/confirm.sh"
chmod 700 "$B/rollback.sh" "$B/timeout.sh" "$B/confirm.sh"
trap 'rc=$?; [ "$rc" = 0 ] || sh "$B/rollback.sh"; exit "$rc"' EXIT
cp "$S/boot-guard" /etc/init.d/scut-ath11k-guard.new
chmod 755 /etc/init.d/scut-ath11k-guard.new
mv /etc/init.d/scut-ath11k-guard.new /etc/init.d/scut-ath11k-guard
echo allowed > "$B/state.new"
mv "$B/state.new" "$B/state"
/etc/init.d/scut-ath11k-guard enable
for m in ath11k.ko ath11k_ahb.ko; do
    cp "$S/$m" "$K/$m.new"
    chmod 644 "$K/$m.new"
    mv "$K/$m.new" "$K/$m"
done
sha256sum "$K/ath11k.ko" "$K/ath11k_ahb.ko"
sha256sum -c "$B/preserved.sha256"
sync
echo 'Modules staged. Running kernel remains original until approved reboot.'
