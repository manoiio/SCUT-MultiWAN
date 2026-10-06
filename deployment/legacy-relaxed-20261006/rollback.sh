#!/bin/sh
# Restore only this round's code; do not undo healthy associations or sessions.
set -eu
umask 077
BACKUP=/root/scut-multiwan-legacy-relaxed-backup-20261006
. /usr/lib/scut-multiwan/common.sh
mw_require_active 30
mw_lock legacy-code-deploy 8
exec 5>>/tmp/scut-multiwan-locks/native-watchdog; flock -n 5 || exit 75
exec 4>>/tmp/scut-multiwan-locks/usb-watchdog; flock -n 4 || exit 75
exec 6>>/tmp/scut-multiwan-locks/native-best; flock -n 6 || exit 75
mw_lock qca-phy0-sta0 7
exec 3>>/tmp/scut-multiwan-locks/qca-phy2-sta0; flock -n 3 || exit 75
mw_portal_lock 5
cd "$BACKUP"
sha256sum -c original.sha256
for file in scut-link-recover scut-rate-watchdog; do test -s "$file"; sh -n "$file"; done
mkdir /tmp/scut-multiwan-deploying
trap 'rmdir /tmp/scut-multiwan-deploying' EXIT
# Convert only transient recovery state; retain every recorded attempt.
for slot in native usb; do
    state="/tmp/scut-link-recover/$slot"
    [ -f "$state" ] || continue
    read -r version attempt failures retry healthy < "$state"
    if [ "$version" = v2 ]; then
        case "$attempt" in ''|*[!0-9]*) exit 1;; esac
        printf 'none 0 0 %s\n' "$attempt" > "$state.rollback.$$"
        mv "$state.rollback.$$" "$state"
    fi
done
for file in scut-link-recover scut-rate-watchdog; do
    dest="/usr/bin/$file"
    cp -p "$file" "$dest.legacy-rollback.$$"
    sh -n "$dest.legacy-rollback.$$"
    mv "$dest.legacy-rollback.$$" "$dest"
done
for file in scut-link-recover scut-rate-watchdog; do cmp "$file" "/usr/bin/$file"; done
echo 'original code restored; associations, routes, configuration and session records preserved'
