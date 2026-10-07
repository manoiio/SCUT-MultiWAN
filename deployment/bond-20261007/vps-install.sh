#!/bin/sh
set -eu
STAGE=/tmp/scut-bond-deploy
BACKUP=/root/scut-bond-backup-20261007-v2
for p in /usr/local/bin/scut-bond /etc/scut-bond /etc/systemd/system/scut-bond.service /usr/local/lib/scut-bond; do [ ! -e "$p" ]; done
[ ! -d "$BACKUP" ]
tc qdisc show dev ens18 | grep -q '^qdisc fq_codel 0: root'
for f in scut-bond server.json scut-bond.service scut-bond-queue.service vps-queue.sh rollback.sh; do [ -s "$STAGE/$f" ]; done
sh -n "$STAGE/vps-queue.sh" "$STAGE/rollback.sh"
mkdir -m 700 "$BACKUP"
cp "$STAGE/rollback.sh" "$BACKUP/rollback.sh"; chmod 700 "$BACKUP/rollback.sh"
tc qdisc show dev ens18 > "$BACKUP/qdisc.before"
sha256sum /etc/ssh/sshd_config > "$BACKUP/ssh.before.sha256"
systemd-run --unit=scut-bond-deploy-rollback --on-active=30min /bin/sh "$BACKUP/rollback.sh"
success=0
trap '[ "$success" = 1 ] || sh "$BACKUP/rollback.sh"' EXIT
mkdir -m 700 /etc/scut-bond
! getent passwd scutbond >/dev/null
useradd --system --user-group --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin scutbond
touch "$BACKUP/created-user"
cp "$STAGE/server.json" /etc/scut-bond/server.json
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -sha256 -days 365 -nodes -keyout /etc/scut-bond/server.key -out /etc/scut-bond/server.crt -subj /CN=scut-bond-vps -addext subjectAltName=DNS:scut-bond-vps -addext basicConstraints=critical,CA:TRUE -addext extendedKeyUsage=serverAuth >/dev/null 2>&1
chown -R scutbond:scutbond /etc/scut-bond
chmod 600 /etc/scut-bond/*
cp "$STAGE/scut-bond" /usr/local/bin/scut-bond.new; chmod 755 /usr/local/bin/scut-bond.new; mv /usr/local/bin/scut-bond.new /usr/local/bin/scut-bond
mkdir -m 755 /usr/local/lib/scut-bond
cp "$STAGE/vps-queue.sh" /usr/local/lib/scut-bond/vps-queue.sh; chmod 755 /usr/local/lib/scut-bond/vps-queue.sh
for f in scut-bond.service scut-bond-queue.service; do cp "$STAGE/$f" "/etc/systemd/system/$f.new"; mv "/etc/systemd/system/$f.new" "/etc/systemd/system/$f"; done
systemctl daemon-reload
systemctl enable --now scut-bond-queue.service scut-bond.service
systemctl is-active scut-bond-queue.service scut-bond.service
sha256sum -c "$BACKUP/ssh.before.sha256"
success=1
