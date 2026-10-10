#!/bin/sh
set -eu
umask 077
B=/root/scut-remote-release-backup-20261009
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); test "$n" -lt 50 || exit 75; sleep 1; done
touch /tmp/scut-multiwan-deploying
trap 'rm -f /tmp/scut-multiwan-deploying' EXIT
for file in usr/bin/campus-portal-logout.impl usr/bin/campus-usb-logout.impl; do
 cp -p "$B/$file" "/$file.scut-restore"
 mv "/$file.scut-restore" "/$file"
done
# The new helper is unused by the restored wrappers; retain it as inert data.
# No configuration, session journal, pause, quota or cancellation is changed.
rm -f /tmp/scut-multiwan-deploying
trap - EXIT
