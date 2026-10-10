#!/bin/sh
# School API: unbind_type=1 logs out the request's source, not an arbitrary IP.
# Other-terminal release needs a positively identified account/IP/MAC row.
mw_mac_key() {
    local key
    key=$(printf '%s' "$1" | tr -d ':-' | tr 'A-F' 'a-f')
    case "$key" in ''|*[!0-9a-f]*|000000000000|ffffffffffff) return 75;; esac
    [ "${#key}" = 12 ] || return 75
    printf '%s' "$key"
}
mw_remote_snapshot() {
    local reply json result source_mac target_mac target_ips rc
    mw_require_active 10 || return $?
    mw_session_read "$rr_slot" && [ "$MW_SESSION_IP" = "$rr_target" ] &&
        [ "$MW_SESSION_DEV" = "$rr_owner" ] || return 75
    mw_session_read "$rr_peer" && [ "$MW_SESSION_IP" = "$rr_source" ] &&
        [ "$MW_SESSION_DEV" = "$rr_dev" ] || return 75
    [ "$(ip -4 -o addr show dev "$rr_dev" scope global | awk 'NR==1{split($4,a,"/");print a[1]}')" = "$rr_source" ] || return 75
    rr_query=$((rr_query+1))
    reply=$(printf '%s' "$rr_account" | curl -4 --interface "$rr_dev" --noproxy '*' \
        --silent --fail --max-time 5 --max-filesize 1048576 --get \
        --header 'Cache-Control: no-cache' --data-urlencode "v=$(mw_uptime)-$$-$rr_query" \
        --data-urlencode callback=dr1002 --data-urlencode user_account@/proc/self/fd/0 \
        --data-urlencode login_method=1 --data-urlencode find_mac=0 \
        --data-urlencode "wlan_user_ip=$rr_source" --data-urlencode wlan_user_mac=000000000000 \
        --data-urlencode jsVersion=4.1.3 https://s.scut.edu.cn:802/eportal/portal/mac/find)
    rc=$?; [ "$rc" = 0 ] || return 75
    json=$(printf '%s' "$reply" | sed 's/^dr100[23](//;s/);[[:space:]]*$//')
    result=$(printf '%s' "$json" | jsonfilter -e '@.result' 2>/dev/null) || return 75
    case "$result" in 1|ok) ;; *) return 75;; esac
    # Exactly one source row must match its current hardware MAC. This is a
    # positive control; online_list ignores a different curr_user_ip here.
    source_mac=$(printf '%s' "$json" | jsonfilter -e "@.list[@.online_ip=\"$rr_source\"].online_mac" 2>/dev/null)
    [ "$(mw_mac_key "$source_mac")" = "$rr_source_mac" ] || return 75
    target_mac=$(printf '%s' "$json" | jsonfilter -e "@.list[@.online_ip=\"$rr_target\"].online_mac" 2>/dev/null)
    target_ips=$(printf '%s' "$json" | jsonfilter -e "@.list[@.online_ip=\"$rr_target\"].online_ip" 2>/dev/null)
    rr_found=
    if [ -n "$target_ips" ]; then
        [ "$target_ips" = "$rr_target" ] || return 75
        rr_found=$(mw_mac_key "$target_mac") || return 75
        [ "$rr_found" != "$rr_source_mac" ] || return 75
        [ -n "$rr_owner_mac" ] && [ "$rr_found" = "$rr_owner_mac" ] || return 75
    fi
    mw_session_read "$rr_slot" && [ "$MW_SESSION_IP" = "$rr_target" ] &&
        [ "$MW_SESSION_DEV" = "$rr_owner" ] || return 75
    mw_session_read "$rr_peer" && [ "$MW_SESSION_IP" = "$rr_source" ] &&
        [ "$MW_SESSION_DEV" = "$rr_dev" ] || return 75
    [ "$(ip -4 -o addr show dev "$rr_dev" scope global | awk 'NR==1{split($4,a,"/");print a[1]}')" = "$rr_source" ] || return 75
    [ "$(mw_mac_key "$(cat "/sys/class/net/$rr_dev/address" 2>/dev/null)")" = "$rr_source_mac" ] || return 75
}
mw_remote_release() {
    local rr_slot rr_target rr_account rr_owner rr_peer rr_dev rr_source rr_source_mac rr_owner_mac rr_found rr_first
    local peer_account num reply json result rc n absent rr_query
    rr_query=0
    MW_REMOTE_STAGE=peer-admission
    rr_slot=$1; rr_target=$2; rr_account=$3
    case "$rr_slot" in native) rr_peer=usb; peer_account=${USB_USER:-$NATIVE_USER};; usb) rr_peer=native; peer_account=$NATIVE_USER;; *) return 75;; esac
    case "$peer_account" in *@wifi) ;; *) peer_account=${peer_account}@wifi;; esac
    [ "$peer_account" = "$rr_account" ] || return 75
    mw_session_read "$rr_slot" && [ "$MW_SESSION_IP" = "$rr_target" ] || return 75
    rr_owner=$MW_SESSION_DEV
    rr_owner_mac=$(mw_mac_key "$(cat "/sys/class/net/$rr_owner/address" 2>/dev/null)") || rr_owner_mac=
    mw_session_read "$rr_peer" && [ "$MW_SESSION_IP" != none ] || return 75
    rr_dev=$MW_SESSION_DEV; rr_source=$MW_SESSION_IP
    [ "$rr_source" != "$rr_target" ] || return 75
    rr_source_mac=$(mw_mac_key "$(cat "/sys/class/net/$rr_dev/address" 2>/dev/null)") || return 75
    mw_online "$rr_dev" 4 || return 75
    MW_REMOTE_STAGE=target-lookup
    mw_remote_snapshot || return $?
    rr_first=$rr_found
    sleep 1
    mw_remote_snapshot || return $?
    [ "$rr_found" = "$rr_first" ] || return 75
    if [ -z "$rr_first" ]; then
        if [ "${MW_MANUAL_LOGIN:-0}" != 1 ]; then mw_pause_login "$rr_slot" vanished || return 75; return 75; fi
    else
        MW_REMOTE_STAGE=target-unbind
        mw_require_active 20 || return $?
        num=$(printf '%s\n' "$rr_target" | awk -F. '{printf "%.0f",$1*16777216+$2*65536+$3*256+$4}')
        reply=$(printf '%s' "$rr_account" | curl -4 --interface "$rr_dev" --noproxy '*' \
            --silent --fail --max-time 10 --max-filesize 1048576 --get \
            --data-urlencode callback=dr1002 --data-urlencode user_account@/proc/self/fd/0 \
            --data-urlencode "wlan_user_mac=$(printf '%s' "$rr_first" | tr 'a-f' 'A-F')" --data-urlencode "wlan_user_ip=$num" \
            --data-urlencode unbind_type=2 --data-urlencode jsVersion=4.1.3 \
            https://s.scut.edu.cn:802/eportal/portal/mac/unbind)
        rc=$?; [ "$rc" = 0 ] || return 75
        json=$(printf '%s' "$reply" | sed 's/^dr100[23](//;s/);[[:space:]]*$//')
        result=$(printf '%s' "$json" | jsonfilter -e '@.result' 2>/dev/null) || return 75
        case "$result" in 1|ok) ;; *) return 75;; esac
        MW_REMOTE_STAGE=target-confirm
        n=0; absent=0
        while [ "$n" -lt 5 ]; do
            mw_remote_snapshot || return $?
            if [ -z "$rr_found" ]; then absent=$((absent+1)); else absent=0; fi
            [ "$absent" -lt 2 ] || break
            n=$((n+1))
            sleep 2
        done
        [ "$absent" -ge 2 ] || return 75
    fi
    MW_REMOTE_STAGE=peer-public
    mw_online "$rr_dev" 4 || return 75
    # Revalidate both journals and source identity once more before clearing.
    mw_remote_snapshot && [ -z "$rr_found" ] || return 75
    mw_session_clear "$rr_slot" "$rr_target" || return 75
    logger -t campus-portal "$rr_slot exact remote target release verified; peer remains online"
}
mw_remote_release_logged() {
    local rc
    mw_remote_release "$@"; rc=$?
    logger -t campus-portal "$1 remote-release stage=$MW_REMOTE_STAGE rc=$rc"
    if [ "${MW_LINK_DETAIL:-}" = "/etc/scut-multiwan/$1.last-detail" ]; then
        printf 'remote-release: stage=%s rc=%s\n' "$MW_REMOTE_STAGE" "$rc" >> "$MW_LINK_DETAIL"
    fi
    return "$rc"
}
