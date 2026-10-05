#!/bin/sh
# Bound to the 2026-10-06 wired deployment; never delete uncertain journals.
set -eu
B=/root/scut-multiwan-wired-backup-20261006
[ -f "$B/files.list" ] || exit 1
if [ -f /etc/scut-multiwan/wired.session ]; then
    read -r ip dev extra < /etc/scut-multiwan/wired.session
    [ "$dev" = wan ] && [ -z "$extra" ] || exit 75
    if [ "$ip" != none ]; then
        . /usr/lib/scut-multiwan/common.sh
        mw_require_active 10 || exit $?
        # Also handle a shell wrapper from the first acceptance revision.
        if [ -f /tmp/scut-wired-ready ]; then
            read -r pid started extra < /tmp/scut-wired-ready
            case "$pid:$started" in *[!0-9:]*) exit 75;; esac
            if [ -n "$pid" ] && [ -n "$started" ] && [ -z "$extra" ] &&
               [ "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$started" ] &&
               [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = /usr/bin/scutclient-wired ]; then
                kill -TERM "$pid"
            fi
        fi
        /etc/init.d/scut-wired stop
        /usr/bin/scutclient-wired --release || exit $?
    fi
fi
. /usr/lib/scut-multiwan/common.sh
mw_portal_lock 0 route || exit $?
touch /tmp/scut-multiwan-deploying
trap 'rm -f /tmp/scut-multiwan-deploying' EXIT
[ ! -x /etc/init.d/scut-wired ] || /etc/init.d/scut-wired stop
[ ! -x /etc/init.d/scut-wired ] || /etc/init.d/scut-wired disable
while read -r target; do
    if [ -f "$B/files$target" ]; then
        cp -p "$B/files$target" "$target.wired-restore"
        mv "$target.wired-restore" "$target"
    elif grep -Fxq "$target" "$B/absent.list"; then
        rm -f "$target"
    else exit 1; fi
done < "$B/files.list"
ubus call network reload
rm -f /tmp/scut-multiwan-deploying /tmp/scut-wired-ready "$B/armed"
trap - EXIT
exec 9>&-
/usr/bin/dualwan-refresh apply
echo wired-rollback-complete
