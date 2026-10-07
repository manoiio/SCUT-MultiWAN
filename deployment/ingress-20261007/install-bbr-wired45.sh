#!/bin/sh
set -eu
B=/root/scut-bond-bbr-wired45-backup-20261007
S=/tmp/scut-bbr50-20261007
test ! -e "$B"
test -s "$S/scut-bond"
test "$(sha256sum "$S/scut-bond" | cut -d' ' -f1)" = 82cf58bd6533bf129e210462deb523353ff89d9c7e23d83fa6c8e1e792e6d827
test ! -e /etc/modules-load.d/scut-bond-bbr.conf
test -z "$(ss -Hnti 'sport = :57501')"
test "$(sha256sum /usr/local/bin/scut-bond | cut -d' ' -f1)" = d8627d14b6c6fac856a425d7709f3bdf26cdb6ac044a5130a18bce94dcd8b0c9
test "$(sha256sum /usr/local/lib/scut-bond/vps-queue.sh | cut -d' ' -f1)" = 32aa5b1d0d52db985b4c7d25c4ce3f0925679e6417fe6d0e3d88a784cb153eb0
umask 077
mkdir "$B"; chmod 700 "$B"
cp -p /usr/local/bin/scut-bond "$B/scut-bond"
cp -p /etc/scut-bond/server.json "$B/server.json"
cp -p /usr/local/lib/scut-bond/vps-queue.sh "$B/vps-queue.sh"
cat > "$B/restore-queue.sh" <<'RESTORE'
#!/bin/sh
set -eu
tc qdisc del dev ens18 root
tc qdisc replace dev ens18 root handle 1: prio bands 3 priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
tc qdisc add dev ens18 parent 1:1 handle 10: fq_codel
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
tc qdisc add dev ens18 parent 1:3 handle 30: fq quantum 1448 initial_quantum 1448 maxrate 50mbit
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57501 0xffff flowid 1:3
RESTORE
cat > "$B/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
B=/root/scut-bond-bbr-wired45-backup-20261007
systemctl stop scut-bond.service
cp -p "$B/scut-bond" /usr/local/bin/.scut-bond-restore
mv /usr/local/bin/.scut-bond-restore /usr/local/bin/scut-bond
cp -p "$B/server.json" /etc/scut-bond/.server-restore.json
mv /etc/scut-bond/.server-restore.json /etc/scut-bond/server.json
cp -p "$B/vps-queue.sh" /usr/local/lib/scut-bond/.vps-queue-restore.sh
mv /usr/local/lib/scut-bond/.vps-queue-restore.sh /usr/local/lib/scut-bond/vps-queue.sh
rm -f /etc/modules-load.d/scut-bond-bbr.conf
sh "$B/restore-queue.sh"
systemctl start scut-bond.service
modprobe -r tcp_bbr || true
systemctl is-active scut-bond.service
ROLLBACK
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
B=/root/scut-bond-bbr-wired45-backup-20261007
test -e "$B/confirmed" || exec sh "$B/rollback.sh"
GUARD
chmod 700 "$B"/*.sh
sh -n "$B/rollback.sh" "$B/restore-queue.sh" "$B/guard.sh"
systemd-run --unit=scut-bbr-wired45-production-guard-20261007 --on-active=600s --timer-property=AccuracySec=1s /bin/sh "$B/guard.sh"
cat > "$B/new-queue.sh" <<'QUEUE'
#!/bin/sh
set -eu
# Both accepted baselines are owned by this deployment. Recreate the tree so
# this boot service can also be safely invoked for an intentional refresh.
tc qdisc show dev ens18 | grep -Eq '^qdisc (prio 1:|fq_codel 0:) root' || exit 1
if tc qdisc show dev ens18 | grep -q '^qdisc prio 1: root'; then
 tc qdisc del dev ens18 root
fi
tc qdisc replace dev ens18 root handle 1: prio bands 3 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
tc qdisc add dev ens18 parent 1:1 handle 10: fq quantum 1448 initial_quantum 1448 maxrate 45mbit
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
tc qdisc add dev ens18 parent 1:3 handle 30: fq quantum 1448 initial_quantum 1448 maxrate 50mbit
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57501 0xffff match ip dst 110.64.88.149/32 flowid 1:1
tc filter add dev ens18 parent 1: protocol ip pref 2 u32 match ip protocol 6 0xff match ip sport 57501 0xffff flowid 1:3
QUEUE
sh -n "$B/new-queue.sh"
test "$(wc -c < "$B/new-queue.sh")" -gt 900
grep -q 'maxrate 45mbit' "$B/new-queue.sh"
grep -q 'match ip dst 110.64.88.149/32' "$B/new-queue.sh"
systemctl stop scut-bond.service
cp "$S/scut-bond" /usr/local/bin/.scut-bond-new
chmod 755 /usr/local/bin/.scut-bond-new
test "$(sha256sum /usr/local/bin/.scut-bond-new | cut -d' ' -f1)" = "$(sha256sum "$S/scut-bond" | cut -d' ' -f1)"
mv /usr/local/bin/.scut-bond-new /usr/local/bin/scut-bond
sed 's/}/,"congestion_control":"bbr"}/' "$B/server.json" > /etc/scut-bond/.server-new.json
chown scutbond:scutbond /etc/scut-bond/.server-new.json
chmod 600 /etc/scut-bond/.server-new.json
mv /etc/scut-bond/.server-new.json /etc/scut-bond/server.json
cp "$B/new-queue.sh" /usr/local/lib/scut-bond/.vps-queue-new.sh
chmod 755 /usr/local/lib/scut-bond/.vps-queue-new.sh
mv /usr/local/lib/scut-bond/.vps-queue-new.sh /usr/local/lib/scut-bond/vps-queue.sh
printf 'tcp_bbr\n' > /etc/modules-load.d/.scut-bond-bbr-new.conf
chmod 644 /etc/modules-load.d/.scut-bond-bbr-new.conf
mv /etc/modules-load.d/.scut-bond-bbr-new.conf /etc/modules-load.d/scut-bond-bbr.conf
modprobe tcp_bbr
sh /usr/local/lib/scut-bond/vps-queue.sh
systemctl start scut-bond.service
systemctl is-active scut-bond.service
sha256sum /usr/local/bin/scut-bond /usr/local/lib/scut-bond/vps-queue.sh
date -Iseconds
tc qdisc show dev ens18
