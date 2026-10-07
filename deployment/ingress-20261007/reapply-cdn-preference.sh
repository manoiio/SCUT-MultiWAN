#!/bin/sh
# Reapply the accepted candidate after the first guard expired. Baseline bound.
set -eu
B=/root/scut-bond-cdn-preference-backup-20261007
S=/tmp/scut-bbr50-20261007/scut-bond-dns-preferred
test -d "$B"
test ! -e "$B/confirmed"
test "$(sha256sum "$S" | cut -d' ' -f1)" = 7427364d244e6bf761c9d112c6392413a319eb754b0d6fe2d31f0b8ef3214209
test "$(sha256sum /usr/local/bin/scut-bond | cut -d' ' -f1)" = 82cf58bd6533bf129e210462deb523353ff89d9c7e23d83fa6c8e1e792e6d827
test "$(sha256sum /usr/local/lib/scut-bond/vps-queue.sh | cut -d' ' -f1)" = 4fd59c348cf9aa0f9ac9979d65ae531fb6e66c3c0fcc11443b694d670f2285f1
cmp -s /etc/scut-bond/server.json "$B/server.json"
test -z "$(ss -Hnti 'sport = :57501')"
! grep -q preferred_upstream_ipv4 "$B/server.json"
sh -n "$B/rollback.sh" "$B/guard.sh"
umask 077
systemd-run --unit=scut-cdn-preference-final-guard-20261007 --on-active=600s --timer-property=AccuracySec=1s /bin/sh "$B/guard.sh"
systemctl stop scut-bond.service
cp "$S" /usr/local/bin/.scut-bond-dns-new
chmod 755 /usr/local/bin/.scut-bond-dns-new
test "$(sha256sum /usr/local/bin/.scut-bond-dns-new | cut -d' ' -f1)" = 7427364d244e6bf761c9d112c6392413a319eb754b0d6fe2d31f0b8ef3214209
mv /usr/local/bin/.scut-bond-dns-new /usr/local/bin/scut-bond
sed 's/}$/,"preferred_upstream_ipv4":{"cdnfhnfile.115cdn.net":"39.173.161.17"}}/' "$B/server.json" > /etc/scut-bond/.server-dns-new.json
chown scutbond:scutbond /etc/scut-bond/.server-dns-new.json
chmod 600 /etc/scut-bond/.server-dns-new.json
mv /etc/scut-bond/.server-dns-new.json /etc/scut-bond/server.json
systemctl start scut-bond.service
sleep 1
systemctl is-active scut-bond.service
sha256sum /usr/local/bin/scut-bond
date -Iseconds
