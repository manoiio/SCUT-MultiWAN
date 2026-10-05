#!/bin/sh
set -eu
BACKUP=/root/scut-multiwan-backup-20261005-2005
STAGE=/tmp/scut-multiwan-deploy
cd "$STAGE/candidate"
sha256sum -c "$STAGE/candidate.sha256"
while read -r relative; do
    [ -s "$relative" ] || exit 1
    wc -c "$relative"
    sh -n "$relative" || exit 1
    if [ "$relative" != usr/lib/scut-multiwan/common.sh ]; then
        cmp "/$relative" "$BACKUP/$relative" || {
            echo "Live file changed since backup: $relative"; exit 1;
        }
    fi
done < "$STAGE/files.list"
grep -q 'flock -n' usr/lib/scut-multiwan/common.sh
grep -q 'mw_prepare_login native' usr/bin/campus-portal-login.impl
grep -q 'mw_prepare_login usb' usr/bin/campus-usb-login.impl
grep -q 'iif br-lan' usr/bin/dualwan-refresh
grep -q 'phy0-sta\*|phy2-sta\*)' usr/bin/fix-qca-sta-rate
grep -q 'status) status_cmd; exit 0' usr/bin/native-best
# Legacy scripts must be quiescent before their locking scheme is replaced.
if ps w | grep -E '/usr/bin/(native-best|native-watchdog|usb-watchdog|dualwan-refresh|fix-qca-sta-rate|campus-portal-runlocked|campus-.*\.impl)' | grep -v grep >/dev/null; then
    echo 'Maintenance operation active; installation deferred'; exit 75
fi
# An automatic rollback is armed before any live script is replaced.
rm -f "$STAGE/confirmed"
(trap '' HUP; sleep 240; if [ ! -f /tmp/scut-multiwan-deploy/confirmed ]; then sh /tmp/scut-multiwan-deploy/rollback.sh; fi) </dev/null >"$BACKUP/automatic-rollback.log" 2>&1 &
echo "$!" > "$STAGE/rollback.pid"
echo "$$" > "$STAGE/install.pid"
OWNED=
cleanup() {
    for dir in $OWNED; do
        if [ "$(cat "$dir/pid" 2>/dev/null)" = "$$" ]; then rm -rf "$dir"; fi
    done
    rm -f /tmp/scut-multiwan-deploying
}
failed() {
    trap - EXIT
    cleanup
    sh "$STAGE/rollback.sh"
    exit 1
}
trap failed EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for lock in native-watchdog usb-watchdog native-best dualwan-refresh campus-portal-global fix-qca-sta-rate.phy0-sta0 fix-qca-sta-rate.phy2-sta0; do
    dir="/tmp/$lock.lock"
    mkdir "$dir" || exit 75
    OWNED="$OWNED $dir"
    echo "$$" > "$dir/pid"
done
: > /tmp/scut-multiwan-deploying
mkdir -p /tmp/scut-multiwan-locks
chmod 700 /tmp/scut-multiwan-locks
exec 9>>/tmp/scut-multiwan-locks/portal
flock -n 9 || exit 75
mkdir -p "$BACKUP/runtime"
[ ! -f /tmp/native-watchdog/last_scan ] || cp -p /tmp/native-watchdog/last_scan "$BACKUP/runtime/last_scan"
[ ! -d /tmp/qca-fixed-rate ] || cp -pR /tmp/qca-fixed-rate "$BACKUP/runtime/"
# Seed the two durable slot records only from currently proven online links.
. "$STAGE/candidate/usr/lib/scut-multiwan/common.sh"
NATIVE_DEV=
for iface in wan1 wan2; do
    status="$(ubus call "network.interface.$iface" status)"
    echo "$status" | grep -q '"up":[[:space:]]*true' || continue
    NATIVE_DEV="$(echo "$status" | sed -n 's/^[[:space:]]*"l3_device":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    break
done
USB_DEV="$(ubus call network.interface.usbwan status | sed -n 's/^[[:space:]]*"l3_device":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
case "$NATIVE_DEV" in phy0-sta*|phy2-sta*) ;; *) exit 1;; esac
case "$USB_DEV" in phy3-sta*) ;; *) exit 1;; esac
for slot in native usb; do
    [ "$slot" = native ] && dev="$NATIVE_DEV" || dev="$USB_DEV"
    code="$(curl -4 --interface "$dev" -s --fail --head --max-time 8 -o /dev/null -w '%{http_code}' https://www.baidu.com/)"
    [ "$code" = 200 ] || exit 1
    addr="$(ip -4 -o addr show dev "$dev" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')"
    mw_ipv4 "$addr" || exit 1
    mw_session_write "$slot" "$addr" "$dev" || exit 1
done
# Preserve the existing survey deadline while migrating epoch -> uptime.
if [ -f /tmp/native-watchdog/last_scan ]; then
    old="$(cat /tmp/native-watchdog/last_scan)"
    now="$(date +%s)"; up="$(mw_uptime)"
    case "$old" in ''|*[!0-9]*) old=0;; esac
    if [ "$old" -gt "$up" ] && [ "$old" -le "$now" ]; then
        elapsed=$((now-old)); new=$((up-elapsed))
        [ "$new" -gt 0 ] || new=1
        printf '%s\n' "$new" > /tmp/native-watchdog/last_scan
    fi
fi
# Stage each exact file in /tmp, validate again, then atomically rename it.
while read -r relative; do
    target="/$relative"
    mkdir -p "${target%/*}"
    temp="/tmp/scut-multiwan-newfile-$$"
    cp "$relative" "$temp"
    [ -s "$temp" ] && wc -c "$temp" && sh -n "$temp" || exit 1
    case "$relative" in usr/lib/*) chmod 644 "$temp";; *) chmod 755 "$temp";; esac
    sibling="${target}.scut-new-$$"
    cp -p "$temp" "$sibling"
    sh -n "$sibling" || exit 1
    mv "$sibling" "$target"
    rm -f "$temp"
    cmp "$relative" "$target" || exit 1
done < "$STAGE/files.list"
cleanup
exec 9>&-
trap - EXIT
logger -t scut-multiwan 'stability repair installed; automatic rollback awaiting verification'
echo 'INSTALLED; rollback armed for 240 seconds'
