#!/bin/sh
set -eu
B=/root/scut-ath11k-backup-20261007
K=/lib/modules/6.12.94
if [ "$(readlink /proc/self/fd/6 2>/dev/null)" != "$B/guard.lock" ]; then
    exec 6>>"$B/guard.lock"
fi
flock -n 6 || exit 75
echo '661f0c810d8793c69d3701ee5d5dff5d550ea95894473b7c0427c52d79cca74f  /root/scut-ath11k-backup-20261007/ath11k.ko' | sha256sum -c -
echo '0efa0d8b4554171404f095d8b956702b9f5e15c3edca199c057fe7b7b2a8b2be  /root/scut-ath11k-backup-20261007/ath11k_ahb.ko' | sha256sum -c -
for m in ath11k.ko ath11k_ahb.ko; do
    cp -p "$B/$m" "$K/$m.rollback"
    mv "$K/$m.rollback" "$K/$m"
done
sha256sum -c "$B/modules-before.sha256"
echo rolled-back > "$B/state.new"
mv "$B/state.new" "$B/state"
/etc/init.d/scut-ath11k-guard disable
sync
