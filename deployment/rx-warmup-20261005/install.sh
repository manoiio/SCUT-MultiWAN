#!/bin/sh
set -eu
S=/tmp/scut-rx-warmup-deploy-20261005
B=/root/scut-multiwan-rx-warmup-backup-20261005
F=/usr/bin/fix-qca-sta-rate
[ ! -e "$B" ] && [ ! -e /tmp/scut-multiwan-deploying ] || exit 75
[ -s "$S/fix-qca-sta-rate" ] || exit 1
wc -c "$S/fix-qca-sta-rate"
sh -n "$S/fix-qca-sta-rate"
sh -n "$S/rollback.sh"
test "$(sha256sum "$S/fix-qca-sta-rate" | awk '{print $1}')" = 99bc84ef538b14d057167d3e390a1020a2f43a3da2b6a2c268cf73e17f7623ef
test "$(sha256sum "$F" | awk '{print $1}')" = 6512291c2c8c82b22dfdf2855a4aa6effdab7657590c8462d331a3a69872465f
. /usr/lib/scut-multiwan/common.sh
mw_require_active 30
mw_portal_lock 30
mw_lock qca-phy0-sta0 7
exec 6>>/tmp/scut-multiwan-locks/qca-phy2-sta0
flock -n 6 || exit 75
[ ! -e /tmp/scut-multiwan-deploying ] || exit 75
test "$(sha256sum "$F" | awk '{print $1}')" = 6512291c2c8c82b22dfdf2855a4aa6effdab7657590c8462d331a3a69872465f
mkdir /tmp/scut-multiwan-deploying
READY=0
DONE=0
cleanup() {
 if [ "$READY" = 1 ] && [ "$DONE" = 0 ]; then
  cp -p "$B/fix-qca-sta-rate" "$F.restore.$$" && mv "$F.restore.$$" "$F"
 fi
 rm -f "$F.new.$$"
 rmdir /tmp/scut-multiwan-deploying
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
mkdir "$B"
cp -p "$F" "$B/fix-qca-sta-rate"
cp "$S/rollback.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
printf '6512291c2c8c82b22dfdf2855a4aa6effdab7657590c8462d331a3a69872465f  fix-qca-sta-rate\n' > "$B/before.sha256"
(cd "$B" && sha256sum -c before.sha256)
sha256sum /etc/config/wireless /etc/config/network /etc/config/firewall /etc/config/system /etc/campus-portal.conf /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/crontabs/root > "$B/unchanged.sha256"
READY=1
cp "$S/fix-qca-sta-rate" "$F.new.$$"
chmod 755 "$F.new.$$"
cmp "$S/fix-qca-sta-rate" "$F.new.$$"
sh -n "$F.new.$$"
mv "$F.new.$$" "$F"
test "$(sha256sum "$F" | awk '{print $1}')" = 99bc84ef538b14d057167d3e390a1020a2f43a3da2b6a2c268cf73e17f7623ef
sha256sum -c "$B/unchanged.sha256"
DONE=1
logger -t scut-multiwan '15-second RX association grace installed; no radio/auth action'
date
echo RX_WARMUP_DEPLOYED
