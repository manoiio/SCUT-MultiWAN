#!/bin/sh
set -eu
B=/root/scut-bond-cdn-preference-backup-20261007
S=/tmp/scut-bbr50-20261007
test ! -e "$B"
test -s "$S/scut-bond-dns-preferred"
test "$(sha256sum "$S/scut-bond-dns-preferred" | cut -d' ' -f1)" = 7427364d244e6bf761c9d112c6392413a319eb754b0d6fe2d31f0b8ef3214209
test "$(sha256sum /usr/local/bin/scut-bond | cut -d' ' -f1)" = 82cf58bd6533bf129e210462deb523353ff89d9c7e23d83fa6c8e1e792e6d827
test "$(sha256sum /usr/local/lib/scut-bond/vps-queue.sh | cut -d' ' -f1)" = 4fd59c348cf9aa0f9ac9979d65ae531fb6e66c3c0fcc11443b694d670f2285f1
test -z "$(ss -Hnti 'sport = :57501')"
! grep -q 'preferred_upstream_ipv4' /etc/scut-bond/server.json
umask 077
mkdir "$B"; chmod 700 "$B"
cp -p /usr/local/bin/scut-bond "$B/scut-bond"
cp -p /etc/scut-bond/server.json "$B/server.json"
cat > "$B/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
B=/root/scut-bond-cdn-preference-backup-20261007
systemctl stop scut-bond.service
cp -p "$B/scut-bond" /usr/local/bin/.scut-bond-dns-restore
mv /usr/local/bin/.scut-bond-dns-restore /usr/local/bin/scut-bond
cp -p "$B/server.json" /etc/scut-bond/.server-dns-restore.json
mv /etc/scut-bond/.server-dns-restore.json /etc/scut-bond/server.json
systemctl start scut-bond.service
systemctl is-active scut-bond.service
ROLLBACK
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
B=/root/scut-bond-cdn-preference-backup-20261007
test -e "$B/confirmed" || exec sh "$B/rollback.sh"
GUARD
chmod 700 "$B"/*.sh
sh -n "$B/rollback.sh" "$B/guard.sh"
systemd-run --unit=scut-cdn-preference-guard-20261007 --on-active=600s --timer-property=AccuracySec=1s /bin/sh "$B/guard.sh"
systemctl stop scut-bond.service
cp "$S/scut-bond-dns-preferred" /usr/local/bin/.scut-bond-dns-new
chmod 755 /usr/local/bin/.scut-bond-dns-new
test "$(sha256sum /usr/local/bin/.scut-bond-dns-new | cut -d' ' -f1)" = "$(sha256sum "$S/scut-bond-dns-preferred" | cut -d' ' -f1)"
mv /usr/local/bin/.scut-bond-dns-new /usr/local/bin/scut-bond
sed 's/}$/,"preferred_upstream_ipv4":{"cdnfhnfile.115cdn.net":"39.173.161.17"}}/' "$B/server.json" > /etc/scut-bond/.server-dns-new.json
chown scutbond:scutbond /etc/scut-bond/.server-dns-new.json
chmod 600 /etc/scut-bond/.server-dns-new.json
mv /etc/scut-bond/.server-dns-new.json /etc/scut-bond/server.json
systemctl start scut-bond.service
sleep 1
systemctl is-active scut-bond.service
ss -lnt 'sport = :57501'
sha256sum /usr/local/bin/scut-bond /usr/local/lib/scut-bond/vps-queue.sh
date -Iseconds
