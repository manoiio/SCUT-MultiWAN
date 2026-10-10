#!/bin/sh
set -eu
B=/root/scut-lan-modes-backup-20261007
[ ! -x /root/scut-lan-proxy-backup-20261007/rollback.sh ] || sh /root/scut-lan-proxy-backup-20261007/rollback.sh
/etc/init.d/scut-lan-mode disable 2>/dev/null || :
/etc/init.d/scut-lan-mode stop 2>/dev/null || :
/etc/init.d/scut-lan-dns stop 2>/dev/null || :
/etc/init.d/scut-lan-tunnel stop 2>/dev/null || :
for family in -4 -6; do
    ip "$family" rule del pref 90 iif br-lan lookup 106 >/dev/null 2>&1 || :
    ip "$family" route flush table 106 >/dev/null 2>&1 || :
done
ip -4 rule del pref 91 from 172.31.255.2/32 lookup 106 >/dev/null 2>&1 || :
for table in 103 106; do ip -4 rule del pref 94 fwmark 0x5343 lookup "$table" >/dev/null 2>&1 || :; done
nft delete table inet scut_lan_mode >/dev/null 2>&1 || :
nft delete table inet scut_lan_switch >/dev/null 2>&1 || :
ip tuntap del dev scut-lan mode tun >/dev/null 2>&1 || :
cp -p "$B/firewall" /etc/config/.firewall.scut-restore
mv /etc/config/.firewall.scut-restore /etc/config/firewall
cp -p "$B/dhcp" /etc/config/.dhcp.scut-restore
mv /etc/config/.dhcp.scut-restore /etc/config/dhcp
/etc/init.d/firewall reload
/etc/init.d/odhcpd reload
printf 'multi\n' > /etc/scut-lan/mode
# New files and TUN module remain disabled for diagnosis; old services unchanged.
