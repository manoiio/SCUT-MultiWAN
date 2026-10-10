#!/bin/sh
# Definitions only. Session journals are never erased to bypass admission.
mw_login_paused() {
    case "$1" in native|usb|wan) ;; *) return 75;; esac
    if [ -e /etc/scut-multiwan/morning-random.enabled ]; then
        mw_clock || return 76
        if [ "$MW_SECONDS" -ge 25200 ] && [ "$MW_SECONDS" -le 27600 ]; then
            mw_morning_time || return 76
            case "$1" in native) MW_SLOT_START=$MW_NATIVE_START;; usb) MW_SLOT_START=$MW_USB_START;; wan) MW_SLOT_START=$MW_WAN_START;; esac
            [ "$MW_SECONDS" -ge "$MW_SLOT_START" ] || return 76
        fi
    fi
    [ "${MW_MANUAL_LOGIN:-0}" = 1 ] && return 0
    [ ! -e "/etc/scut-multiwan/$1.login-paused" ] || return 75
}
mw_pause_login() {
    case "$1" in native|usb|wan) ;; *) return 2;; esac
    case "$2" in vanished|manual|logout|morning) ;; *) return 2;; esac
    mkdir -p /etc/scut-multiwan || return 1
    (umask 077; printf '%s\n' "$2" > "/etc/scut-multiwan/$1.login-paused.new") || return 1
    mv "/etc/scut-multiwan/$1.login-paused.new" "/etc/scut-multiwan/$1.login-paused" || return 1
    if [ "$2" = logout ]; then
        # A logout before today's drawn time also consumes today's admission.
        # Tomorrow has a different date and remains eligible for one attempt.
        mw_clock || return 76
        (umask 077; printf '%s\n' "$MW_DATE" > "/etc/scut-multiwan/$1.morning-claimed.new") || return 1
        mv "/etc/scut-multiwan/$1.morning-claimed.new" "/etc/scut-multiwan/$1.morning-claimed" || return 1
        printf '%s\n' "$MW_DATE" > "/etc/scut-multiwan/$1.morning-cancelled.new" || return 1
        mv "/etc/scut-multiwan/$1.morning-cancelled.new" "/etc/scut-multiwan/$1.morning-cancelled" || return 1
    fi
    return 0
}
mw_portal_empty() {
    local json result msg
    # Accept a complete object or the school's known JSONP callback only.
    json=$(printf '%s' "$1" | sed 's/^dr100[23](//;s/);[[:space:]]*$//')
    result=$(printf '%s' "$json" | jsonfilter -e '@.result' 2>/dev/null) || return 1
    msg=$(printf '%s' "$json" | jsonfilter -e '@.msg' 2>/dev/null) || return 1
    [ "$result" = 0 ] && [ "$msg" = '获取用户在线信息数据为空！' ]
}
mw_confirm_absent() {
    local slot dev target current num reply rc n
    slot=$1; dev=$2; target=$3
    mw_portal_empty "$4" || return 1
    mw_session_read "$slot" && [ "$MW_SESSION_IP" = "$target" ] || return 1
    # The current source IP must be the exact recorded target. A different
    # source may be querying its own state; that cannot release a stale IP.
    current=$(ip -4 -o addr show dev "$dev" scope global | awk 'NR==1{split($4,a,"/");print a[1]}')
    [ "$current" = "$target" ] || return 1
    num=$(printf '%s\n' "$target" | awk -F. '{printf "%.0f",$1*16777216+$2*65536+$3*256+$4}')
    n=0
    while [ "$n" -lt 2 ]; do
        mw_require_active 8 || return $?
        reply=$(curl -4 --interface "$dev" --noproxy '*' --silent --fail --max-time 5 \
            --max-filesize 1048576 --get --data-urlencode callback=dr1002 \
            --header 'Cache-Control: no-cache' --data-urlencode "v=$(mw_uptime)-$n" \
            --data-urlencode user_account= --data-urlencode user_password= \
            --data-urlencode wlan_user_mac=000000000000 --data-urlencode "curr_user_ip=$num" \
            --data-urlencode jsVersion=4.1.3 https://s.scut.edu.cn:802/eportal/portal/online_list)
        rc=$?
        [ "$rc" = 0 ] && mw_portal_empty "$reply" || return 1
        [ "$(ip -4 -o addr show dev "$dev" scope global | awk 'NR==1{split($4,a,"/");print a[1]}')" = "$target" ] || return 1
        mw_session_read "$slot" && [ "$MW_SESSION_IP" = "$target" ] || return 1
        n=$((n+1))
    done
    if [ "${MW_MANUAL_LOGIN:-0}" != 1 ]; then
        mw_pause_login "$slot" vanished || return 1
        logger -t campus-portal "$slot recorded session confirmed absent; automatic login paused until manual or daily morning start"
        return 75
    fi
    # Manual/morning admission can proceed after the two exact-IP checks.
    mw_session_clear "$slot" "$target"
}

# One persistent draw per local date, protected independently from Portal.
mw_morning_time() {
    local day native usb wan extra random seconds h1 h2 h3
    [ -e /etc/scut-multiwan/morning-random.enabled ] || { MW_MORNING=25200; return 0; }
    mkdir -p /etc/scut-multiwan /tmp/scut-multiwan-locks || return 1
    exec 3>>/tmp/scut-multiwan-locks/morning-draw || return 1
    flock -n 3 || { exec 3>&-; return 1; }
    read -r day native usb wan extra 2>/dev/null < /etc/scut-multiwan/morning-time || day=
    if [ "$day" != "$MW_DATE" ]; then
        # This BusyBox image has no od. The kernel UUID contains independent
        # random bits before the version field and requires no new package.
        random=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
        case "$random" in ''|*[!0-9a-f]*) flock -u 3; exec 3>&-; return 1;; esac
        [ "${#random}" = 32 ] || { flock -u 3; exec 3>&-; return 1; }
        h1=$(printf '%s' "$random" | cut -c1-4); h2=$(printf '%s' "$random" | cut -c5-8); h3=$(printf '%s' "$random" | cut -c9-12)
        native=$((25200+0x$h1%2401)); usb=$((25200+0x$h2%2401)); wan=$((25200+0x$h3%2401))
        # Independent draws, while keeping the three starts distinct.
        [ "$usb" != "$native" ] || usb=$((25200+(usb-25200+1)%2401))
        while [ "$wan" = "$native" ] || [ "$wan" = "$usb" ]; do wan=$((25200+(wan-25200+1)%2401)); done
        (umask 077; printf '%s %s %s %s\n' "$MW_DATE" "$native" "$usb" "$wan" > /etc/scut-multiwan/morning-time.new) &&
            mv /etc/scut-multiwan/morning-time.new /etc/scut-multiwan/morning-time || { flock -u 3; exec 3>&-; return 1; }
        extra=
    fi
    flock -u 3; exec 3>&-
    [ -z "$extra" ] || return 1
    for seconds in "$native" "$usb" "$wan"; do
        case "$seconds" in ''|*[!0-9]*) return 1;; esac
        [ "$seconds" -ge 25200 ] && [ "$seconds" -le 27600 ] || return 1
    done
    [ "$native" != "$usb" ] && [ "$native" != "$wan" ] && [ "$usb" != "$wan" ] || return 1
    MW_NATIVE_START=$native; MW_USB_START=$usb; MW_WAN_START=$wan
    MW_MORNING=$native
    [ "$usb" -ge "$MW_MORNING" ] || MW_MORNING=$usb
    [ "$wan" -ge "$MW_MORNING" ] || MW_MORNING=$wan
}
