#!/bin/sh
set -eu
modprobe tun
ip link show scut-lan >/dev/null 2>&1 || ip tuntap add dev scut-lan mode tun user scutbond
ip addr replace 172.31.255.1/30 dev scut-lan
ip -6 addr replace fd70:7363:7574::1/126 dev scut-lan nodad
ip link set scut-lan mtu 1400 up
# Preserve IPv6 router advertisements when forwarding is enabled.
sysctl -q -w net.ipv6.conf.ens18.accept_ra=2
sysctl -q -w net.ipv4.ip_forward=1
sysctl -q -w net.ipv6.conf.all.forwarding=1
nft list table inet scut_lan_vps >/dev/null 2>&1 || nft add table inet scut_lan_vps
nft -f - <<'NFT'
delete table inet scut_lan_vps
table inet scut_lan_vps {
 chain forward { type filter hook forward priority -5; policy accept;
  iifname "scut-lan" oifname "ens18" accept
  iifname "scut-lan" drop
  oifname "scut-lan" ct state established,related accept
  oifname "scut-lan" drop
 }
 chain postnat { type nat hook postrouting priority srcnat; policy accept;
  oifname "ens18" ip saddr 172.31.255.2 masquerade
  oifname "ens18" ip6 saddr fd70:7363:7574::2 masquerade
 }
}
NFT
# Add only two filters; retain the accepted 57501 queues and ordinary traffic.
tc filter replace dev ens18 parent 1: protocol ip pref 3 u32 match ip protocol 6 0xff match ip sport 57502 0xffff match ip dst 110.64.88.149/32 flowid 1:1
tc filter replace dev ens18 parent 1: protocol ip pref 4 u32 match ip protocol 6 0xff match ip sport 57502 0xffff flowid 1:3
