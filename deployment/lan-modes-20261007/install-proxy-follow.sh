#!/bin/sh
set -eu
B=/root/scut-lan-proxy-backup-20261007
S=/tmp/scut-lan-stage
test ! -e "$B"
test -s "$S/scut-lan-proxy-follow"
test -s "$S/scut-lan-mode-follow"
test -z "$(ip -4 rule show | awk '$1=="94:"')"
sh -n "$S/scut-lan-mode-follow"
umask 077
mkdir "$B"
cp -p /usr/bin/scut-bond "$B/scut-bond"
cp -p /etc/scut-bond/client.json "$B/client.json"
cp -p /usr/bin/scut-lan-mode "$B/scut-lan-mode"
cp "$S/rollback-proxy-follow.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
sleep 900
test -e /root/scut-lan-proxy-backup-20261007/confirmed || exec sh /root/scut-lan-proxy-backup-20261007/rollback.sh
GUARD
nohup sh "$B/guard.sh" > "$B/guard.log" 2>&1 </dev/null &
echo "$!" > "$B/guard.pid"
cp "$S/scut-lan-proxy-follow" /usr/bin/.scut-bond-lan.new
chmod 755 /usr/bin/.scut-bond-lan.new
/usr/bin/.scut-bond-lan.new -config "$B/client.json" -derive-lan-client-config > /etc/scut-bond/.client-lan.new.json
chmod 600 /etc/scut-bond/.client-lan.new.json
cp "$S/scut-lan-mode-follow" /usr/bin/.scut-lan-mode.new
chmod 755 /usr/bin/.scut-lan-mode.new
mv /usr/bin/.scut-lan-mode.new /usr/bin/scut-lan-mode
/usr/bin/scut-lan-mode refresh
mv /usr/bin/.scut-bond-lan.new /usr/bin/scut-bond
mv /etc/scut-bond/.client-lan.new.json /etc/scut-bond/client.json
/etc/init.d/scut-bond restart
sleep 3
/usr/bin/scut-lan-mode status
sha256sum /usr/bin/scut-bond
ubus call service list '{"name":"scut-bond"}' | jsonfilter -e '@["scut-bond"].instances.proxy.pid'
