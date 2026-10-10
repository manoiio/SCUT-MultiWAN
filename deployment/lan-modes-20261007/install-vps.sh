#!/bin/sh
set -eu
B=/root/scut-lan-modes-backup-20261007
S=/tmp/scut-lan-stage
test ! -e "$B"
test ! -e /etc/scut-lan
test -s "$S/scut-lan-tunnel"
test -z "$(ss -Hln 'sport = :57502')"
test -z "$(ip -4 route show table 106 2>/dev/null)"
umask 077
mkdir "$B" /etc/scut-lan
sysctl -n net.ipv4.ip_forward > "$B/forward4"
sysctl -n net.ipv6.conf.all.forwarding > "$B/forward6"
sysctl -n net.ipv6.conf.ens18.accept_ra > "$B/accept-ra"
cp "$S/scut-lan-tunnel" /usr/local/bin/.scut-lan-tunnel.new
chmod 755 /usr/local/bin/.scut-lan-tunnel.new
mv /usr/local/bin/.scut-lan-tunnel.new /usr/local/bin/scut-lan-tunnel
/usr/local/bin/scut-lan-tunnel -config /etc/scut-bond/server.json -derive-packet-config server > /etc/scut-lan/server.json
chown scutbond:scutbond /etc/scut-lan/server.json
chown root:scutbond /etc/scut-lan
chmod 750 /etc/scut-lan
mkdir -p /usr/local/lib/scut-lan
cp "$S/vps-setup.sh" /usr/local/lib/scut-lan/vps-setup.sh
chmod 755 /usr/local/lib/scut-lan/vps-setup.sh
cp "$S/scut-lan-setup.service" "$S/scut-lan-tunnel.service" /etc/systemd/system/
cp "$S/rollback-vps.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
test -e /root/scut-lan-modes-backup-20261007/confirmed || exec sh /root/scut-lan-modes-backup-20261007/rollback.sh
GUARD
systemd-run --unit=scut-lan-modes-guard-20261007 --on-active=1200s --timer-property=AccuracySec=1s /bin/sh "$B/guard.sh"
systemctl daemon-reload
systemctl enable --now scut-lan-tunnel.service
systemctl is-active scut-lan-setup.service scut-lan-tunnel.service
ss -lnt 'sport = :57502'
sha256sum /usr/local/bin/scut-lan-tunnel
