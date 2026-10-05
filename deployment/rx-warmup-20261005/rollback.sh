#!/bin/sh
set -eu
B=/root/scut-multiwan-rx-warmup-backup-20261005
F=/usr/bin/fix-qca-sta-rate
(cd "$B" && sha256sum -c before.sha256)
mkdir -p /tmp/scut-multiwan-locks
exec 9>>/tmp/scut-multiwan-locks/portal
flock -n 9 || exit 75
exec 7>>/tmp/scut-multiwan-locks/qca-phy0-sta0
flock -n 7 || exit 75
exec 6>>/tmp/scut-multiwan-locks/qca-phy2-sta0
flock -n 6 || exit 75
[ ! -e /tmp/scut-multiwan-deploying ] || exit 75
mkdir /tmp/scut-multiwan-deploying
trap 'rmdir /tmp/scut-multiwan-deploying' EXIT
cp -p "$B/fix-qca-sta-rate" "$F.rollback.$$"
sh -n "$F.rollback.$$"
mv "$F.rollback.$$" "$F"
test "$(sha256sum "$F" | awk '{print $1}')" = 6512291c2c8c82b22dfdf2855a4aa6effdab7657590c8462d331a3a69872465f
date
echo RX_WARMUP_ROLLED_BACK
