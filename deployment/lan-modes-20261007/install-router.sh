#!/bin/sh
set -eu
B=/root/scut-lan-modes-backup-20261007
S=/tmp/scut-lan-stage
test -s "$B/firewall"
test -s "$B/dhcp"
test ! -e /usr/bin/scut-lan-mode
test ! -e /etc/scut-lan
test -z "$(ip -4 route show table 106 2>/dev/null)"
test -z "$(ip -6 route show table 106 2>/dev/null)"
test -z "$(ip -4 rule show | awk '$1=="90:"||$1=="91:"')"
test -z "$(ip -6 rule show | awk '$1=="90:"')"
umask 077
mkdir /etc/scut-lan
printf 'multi\n' > /etc/scut-lan/mode
cp "$S/rollback-router.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
sleep 1200
test -e /root/scut-lan-modes-backup-20261007/confirmed || exec sh /root/scut-lan-modes-backup-20261007/rollback.sh
GUARD
chmod 700 "$B/guard.sh"
nohup sh "$B/guard.sh" > "$B/guard.log" 2>&1 </dev/null &
echo "$!" > "$B/guard.pid"
while read -r rel; do
    test -s "$S/root/$rel"
    case "$rel" in *.sh|usr/bin/*|usr/libexec/*|etc/init.d/*|etc/hotplug.d/*) sh -n "$S/root/$rel";; esac
    dir=${rel%/*}
    mkdir -p "/$dir"
    test ! -e "/$rel"
    cp "$S/root/$rel" "/$rel.new"
    case "$rel" in usr/bin/*|usr/libexec/*|etc/init.d/*|etc/hotplug.d/*) chmod 755 "/$rel.new";; *) chmod 644 "/$rel.new";; esac
    mv "/$rel.new" "/$rel"
done < "$S/router-files.txt"
cp "$S/scut-lan-tunnel" /usr/bin/.scut-lan-tunnel.new
chmod 755 /usr/bin/.scut-lan-tunnel.new
mv /usr/bin/.scut-lan-tunnel.new /usr/bin/scut-lan-tunnel
/usr/bin/scut-lan-tunnel -config /etc/scut-bond/client.json -derive-packet-config client > /etc/scut-lan/tunnel.json
uci set firewall.scut_lan=zone
uci set firewall.scut_lan.name=scut_lan
uci set firewall.scut_lan.input=DROP
uci set firewall.scut_lan.output=ACCEPT
uci set firewall.scut_lan.forward=DROP
uci add_list firewall.scut_lan.device=scut-lan
uci set firewall.scut_lan_forward=forwarding
uci set firewall.scut_lan_forward.src=lan
uci set firewall.scut_lan_forward.dest=scut_lan
uci commit firewall
uci set dhcp.lan.ra_default=1
uci commit dhcp
/etc/init.d/firewall reload
/etc/init.d/odhcpd reload
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache
/etc/init.d/scut-lan-mode enable
/etc/init.d/scut-lan-mode start
/usr/bin/scut-lan-mode status
sha256sum /usr/bin/scut-lan-tunnel
