#!/bin/sh
set -eu
B=/root/scut-lan-modes-backup-20261007
systemctl disable --now scut-lan-tunnel.service
systemctl stop scut-lan-setup.service
nft delete table inet scut_lan_vps >/dev/null 2>&1 || :
tc filter del dev ens18 parent 1: protocol ip pref 3 >/dev/null 2>&1 || :
tc filter del dev ens18 parent 1: protocol ip pref 4 >/dev/null 2>&1 || :
ip tuntap del dev scut-lan mode tun >/dev/null 2>&1 || :
sysctl -q -w "net.ipv4.ip_forward=$(cat "$B/forward4")"
sysctl -q -w "net.ipv6.conf.all.forwarding=$(cat "$B/forward6")"
sysctl -q -w "net.ipv6.conf.ens18.accept_ra=$(cat "$B/accept-ra")"
rm -f /etc/systemd/system/scut-lan-setup.service /etc/systemd/system/scut-lan-tunnel.service
systemctl daemon-reload
# Private config and candidate binary remain for diagnosis; services are off.
