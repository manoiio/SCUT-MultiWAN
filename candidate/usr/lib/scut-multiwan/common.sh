#!/bin/sh
# Shared BusyBox ash helpers. Locks are stable files: never unlink them.

# Read one local GMT+8 clock snapshot; an uninitialized/invalid clock fails closed.
mw_clock() {
    local clock weekday h m sec extra
    clock="$(date '+%Y-%m-%d %u %H %M %S')" || return 1
    read -r MW_DATE weekday h m sec extra <<EOF
$clock
EOF
    case "$MW_DATE" in 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 1;; esac
    MW_YEAR="${MW_DATE%%-*}"
    [ "$MW_YEAR" -ge 2026 ] && [ -z "$extra" ] || return 1
    case "$weekday" in [1-7]) ;; *) return 1;; esac
    case "$h:$m:$sec" in *[!0-9:]*) return 1;; esac
    [ -n "$h" ] && [ -n "$m" ] && [ -n "$sec" ] || return 1
    h="${h#0}"; m="${m#0}"; sec="${sec#0}"
    [ "${h:-0}" -le 23 ] && [ "${m:-0}" -le 59 ] && [ "${sec:-0}" -le 59 ] || return 1
    MW_WEEKDAY="$weekday"
    MW_SECONDS=$((${h:-0} * 3600 + ${m:-0} * 60 + ${sec:-0}))
}

mw_night_window() {
    mw_clock || return 0
    [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 25200 ]
}

# Weekends require the year's valid workday exceptions; unknown years are quiet.
mw_day_allowed() {
    local stamp mode extra kind next
    MW_DAY_REASON=unknown-calendar
    if [ -e /etc/scut-multiwan/overnight.override ]; then
        read -r stamp mode extra < /etc/scut-multiwan/overnight.override || return 1
        case "$stamp:$mode:$extra" in 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:quiet:|20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:allow:) ;; *) MW_DAY_REASON=invalid-override; return 1;; esac
        if [ "$stamp" = "$MW_DATE" ] && [ "$MW_SECONDS" -lt 25200 ]; then
            MW_DAY_REASON="override-$mode"; [ "$mode" = allow ]; return $?
        fi
    fi
    kind="$(LC_ALL=C awk -v year="$MW_YEAR" -v day="$MW_DATE" \
        -f /usr/lib/scut-multiwan/calendar-check.awk \
        "/etc/scut-multiwan/calendar-$MW_YEAR.txt" 2>/dev/null)" || return 1
    case "$kind" in W) MW_DAY_REASON=make-up-workday; return 1;; H) MW_DAY_REASON=official-holiday; return 0;; esac
    # A next-year notice may include the preceding December's leave dates.
    next=$((MW_YEAR+1))
    kind="$(LC_ALL=C awk -v year="$next" -v day="$MW_DATE" \
        -f /usr/lib/scut-multiwan/calendar-check.awk \
        "/etc/scut-multiwan/calendar-$next.txt" 2>/dev/null)" || kind=
    [ "$kind" != W ] || { MW_DAY_REASON=make-up-workday; return 1; }
    [ "$kind" != H ] || { MW_DAY_REASON=official-holiday; return 0; }
    case "$MW_WEEKDAY" in 6|7) MW_DAY_REASON=rest-weekend; return 0;; esac
    MW_DAY_REASON=ordinary-workday
    return 1
}

# Ordinary/work weekends: 00:06–07:00 quiet. Allowed dates: protect to 00:25.
mw_quiet_now() {
    mw_clock || return 0
    [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 25200 ] || return 1
    mw_day_allowed || return 0
    [ "$MW_SECONDS" -lt 1500 ]
}

# 76 is a policy deferral; 75 is a lock/deployment/unsafe-state deferral.
mw_require_active() {
    [ ! -e /tmp/scut-multiwan-deploying ] || return 75
    mw_quiet_now && return 76
    if [ "$MW_SECONDS" -lt 360 ] &&
       [ $((360 - MW_SECONDS)) -le "${1:-30}" ]; then return 76; fi
    return 0
}

# Health probes/routing never authorize Portal, wireless recovery or scans.
mw_require_route() {
    [ ! -e /tmp/scut-multiwan-deploying ] || return 75
    mw_clock || return 76
    if [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 25200 ]; then
        mw_day_allowed || return 76
        return 0
    fi
    mw_require_active "${1:-30}"
}

mw_require_scan() {
    mw_require_active "${1:-300}" || return $?
    # User sleeps overnight: complete comparisons are scheduled at 07:00.
    [ "$MW_SECONDS" -lt 360 ] || [ "$MW_SECONDS" -ge 25200 ] || return 76
}

mw_guard() {
    case "${1:-active}" in active) mw_require_active;; route) mw_require_route;; *) return 2;; esac
}

mw_uptime() {
    awk '{print int($1)}' /proc/uptime
}

# This BusyBox build has no timeout applet. Bound scans without extra packages.
# Match process start time before signalling, and close watcher lock FDs.
mw_run_bounded() {
    local limit child started timer rc
    limit="$1"; shift
    "$@" & child=$!
    started="$(awk '{print $22}' "/proc/$child/stat" 2>/dev/null)"
    (
        exec 7>&- 8>&- 9>&-
        sleep "$limit"
        if [ -n "$started" ] &&
           [ "$(awk '{print $22}' "/proc/$child/stat" 2>/dev/null)" = "$started" ]; then
            kill -TERM "$child" 2>/dev/null
            sleep 1
            if [ "$(awk '{print $22}' "/proc/$child/stat" 2>/dev/null)" = "$started" ]; then
                kill -KILL "$child" 2>/dev/null
            fi
        fi
    ) & timer=$!
    wait "$child"; rc=$?
    kill -TERM "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
    return "$rc"
}

# FD 8 is an operation lock; FD 7 is reserved for per-device QCA maintenance.
mw_lock() {
    local name fd
    name="$1"; fd="${2:-8}"
    case "$name" in ''|*[!a-zA-Z0-9_.-]*) return 2;; esac
    (umask 077; mkdir -p /tmp/scut-multiwan-locks) || return 1
    chmod 700 /tmp/scut-multiwan-locks || return 1
    case "$fd" in
        7) exec 7>>"/tmp/scut-multiwan-locks/$name" || return 1;;
        8) exec 8>>"/tmp/scut-multiwan-locks/$name" || return 1;;
        *) return 2;;
    esac
    flock -n "$fd" || return 75
}

# FD 9 is inherited by every child in a Portal transaction. Nested wrappers
# reuse the SAME open file description; an environment flag cannot bypass it.
mw_portal_lock() {
    local path waited limit kind
    path=/tmp/scut-multiwan-locks/portal
    kind="${2:-active}"
    if [ "$(readlink /proc/self/fd/9 2>/dev/null)" = "$path" ]; then
        flock -n 9 || return 75
        mw_guard "$kind"
        return $?
    fi
    (umask 077; mkdir -p /tmp/scut-multiwan-locks) || return 1
    chmod 700 /tmp/scut-multiwan-locks || return 1
    exec 9>>"$path" || return 1
    waited=0; limit="${1:-30}"
    while ! flock -n 9; do
        mw_guard "$kind" || return $?
        [ "$waited" -lt "$limit" ] || return 75
        sleep 1
        waited=$((waited + 1))
    done
    mw_guard "$kind"
}

mw_https() {
    local result rc code addr host cache stamp old extra now
    case "$2" in
        https://www.bilibili.com/) host=www.bilibili.com;;
        https://www.jd.com/) host=www.jd.com;;
        *) return 2;;
    esac
    case "$1" in ''|*[!a-zA-Z0-9_.-]*) return 2;; esac
    cache="/tmp/scut-multiwan-health/$1.$host.dns"
    set -- "$1" "$2" "${3:-3}" "${4:-normal}"
    now="$(mw_uptime)"
    if [ "$4" = cached ]; then
        read -r stamp old extra 2>/dev/null < "$cache" || return 1
        case "$stamp" in ''|*[!0-9]*) return 1;; esac
        [ -z "$extra" ] && mw_ipv4 "$old" && [ "$stamp" -le "$now" ] &&
            [ $((now-stamp)) -le 600 ] || return 1
        result="$(curl -4 --interface "$1" --noproxy '*' --silent --fail --head \
            --connect-timeout 2 --max-time "$3" --resolve "$host:443:$old" \
            --output /dev/null --write-out '%{http_code} %{remote_ip}' "$2" 2>/dev/null)"
    else
        result="$(curl -4 --interface "$1" --noproxy '*' --silent --fail --head \
            --connect-timeout 2 --max-time "$3" --output /dev/null \
            --write-out '%{http_code} %{remote_ip}' "$2" 2>/dev/null)"
    fi
    rc=$?
    MW_HEALTH_RC="$rc"
    read -r code addr <<EOF
$result
EOF
    case "$rc:$code" in
        0:200) MW_HEALTH_REASON=online;;
        6:*) MW_HEALTH_REASON=dns; return 1;;
        7:*|28:*) MW_HEALTH_REASON=connect-or-timeout; return 1;;
        35:*|51:*|60:*) MW_HEALTH_REASON=tls; return 1;;
        *) MW_HEALTH_REASON="http-${code:-000}-curl-$rc"; return 1;;
    esac
    # RAM only; write at most once per minute. Never cache an unverified result.
    if [ "$4" != cached ] && mw_ipv4 "$addr"; then
        stamp=0; old=
        read -r stamp old extra 2>/dev/null < "$cache" || stamp=0
        case "$stamp" in ''|*[!0-9]*) stamp=0;; esac
        if [ "$old" != "$addr" ] || [ "$stamp" -gt "$now" ] || [ $((now-stamp)) -ge 60 ]; then
            (umask 077; mkdir -p /tmp/scut-multiwan-health &&
                printf '%s %s\n' "$now" "$addr" > "$cache.$$" && mv "$cache.$$" "$cache") || true
        fi
    fi
    return 0
}

mw_online() {
    local end left cap url
    mw_require_route $((${2:-6} + 2)) || return $?
    end=$(( $(mw_uptime) + ${2:-6} ))
    for url in https://www.bilibili.com/ https://www.jd.com/; do
        left=$((end-$(mw_uptime))); [ "$left" -gt 0 ] || return 1
        cap=3; [ "$left" -ge "$cap" ] || cap="$left"
        mw_https "$1" "$url" "$cap" && return 0
        # Shared resolver failure may be bypassed using a recent verified IP,
        # retaining host/SNI/certificate checks. No permanent CDN pinning.
        if [ "${MW_HEALTH_RC:-0}" = 6 ]; then
            left=$((end-$(mw_uptime))); [ "$left" -gt 1 ] || continue
            cap=2; [ "$left" -gt 2 ] || cap=1
            mw_require_route "$left" || return $?
            mw_https "$1" "$url" "$cap" cached && return 0
        fi
        mw_require_route 2 || return $?
    done
    return 1
}

# Existing session challenges on allowed nights are distinct from new login.
# Work/make-up/unknown nights remain silent; deployment also blocks them.
mw_require_keepalive() {
    [ ! -e /tmp/scut-multiwan-deploying ] || return 75
    mw_clock || return 76
    if [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 25200 ]; then
        mw_day_allowed || return 76
    fi
    return 0
}

# Root-owned budget records, separate from Portal session journals.
mw_night_budget_read() {
    local stored extra
    case "$1" in native|usb) ;; *) return 2;; esac
    read -r stored MW_NCOUNT MW_NLAST MW_NBLOCK extra < "/etc/scut-multiwan/$1.night-budget" || return 75
    case "$stored" in none|20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 75;; esac
    case "$MW_NCOUNT:$MW_NLAST:$MW_NBLOCK" in *[!0-9:]*) return 75;; esac
    [ -n "$MW_NCOUNT" ] && [ -n "$MW_NLAST" ] && [ -z "$extra" ] || return 75
    [ "$MW_NCOUNT" -le 2 ] && [ "$MW_NBLOCK" -le 1 ] || return 75
    if [ "$stored" != "$MW_DATE" ]; then
        [ "$stored" = none ] || [ "$stored" \< "$MW_DATE" ] || return 75
        MW_NCOUNT=0; MW_NLAST=0; MW_NBLOCK=0
    fi
}

mw_night_budget_write() {
    local file tmp
    file="/etc/scut-multiwan/$1.night-budget"; tmp="$file.$$"
    (umask 077; printf '%s %s %s %s\n' "$MW_DATE" "$MW_NCOUNT" "$MW_NLAST" "$MW_NBLOCK" > "$tmp") || return 75
    mv "$tmp" "$file" || return 75
}

mw_night_claim() {
    local now
    mw_clock || return 76
    [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 25200 ] || return 0
    mw_require_active 20 || return $?
    [ "$(readlink /proc/self/fd/9 2>/dev/null)" = /tmp/scut-multiwan-locks/portal ] && flock -n 9 || return 75
    mw_night_budget_read "$1" || return $?
    [ "$MW_NBLOCK" -eq 0 ] && [ "$MW_NCOUNT" -lt 2 ] || return 76
    now="$(date +%s)" || return 75
    case "$now" in ''|*[!0-9]*) return 75;; esac
    [ "$now" -ge 1760000000 ] || return 75
    [ "$MW_NLAST" -eq 0 ] || [ $((now - MW_NLAST)) -ge 900 ] || return 76
    MW_NCOUNT=$((MW_NCOUNT+1)); MW_NLAST="$now"
    # Persist BEFORE releasing an old session or sending any login request.
    mw_night_budget_write "$1"
}

mw_night_block() {
    mw_clock || return 75
    [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 25200 ] || return 0
    mw_night_budget_read "$1" || return $?
    MW_NBLOCK=1
    mw_night_budget_write "$1"
}

mw_scUT_redirect() {
    case "$1" in
        https://s.scut.edu.cn/*|https://s.scut.edu.cn:802/*|http://s.scut.edu.cn/*)
            return 0;;
    esac
    return 1
}

mw_ipv4() {
    printf '%s\n' "$1" | awk -F. '
        NF != 4 {exit 1}
        {for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || $i > 255) exit 1}
        END {if (NF != 4) exit 1}'
}

# Durable slot ledger: IP device, or "none none" after a confirmed unbind.
# Write BEFORE submitting login, so a timeout remains a known occupied slot.
mw_session_write() {
    local file tmp
    case "$1" in native|usb) ;; *) return 2;; esac
    file="/etc/scut-multiwan/$1.session"; tmp="$file.$$"
    [ "$(cat "$file" 2>/dev/null)" = "$2 $3" ] && return 0
    mkdir -p /etc/scut-multiwan || return 1
    chmod 700 /etc/scut-multiwan || return 1
    (umask 077; printf '%s %s\n' "$2" "$3" > "$tmp") || return 1
    mv "$tmp" "$file"
}

mw_record_online() {
    local slot dev ip
    slot="$1"; dev="$2"; ip="$3"
    mw_session_read "$slot" || return 75
    if [ "$MW_SESSION_IP" != none ] && [ "$MW_SESSION_IP" != "$ip" ]; then
        mw_prepare_login "$slot" "$dev" "$ip" || return $?
    fi
    mw_session_write "$slot" "$ip" "$dev"
}

mw_session_read() {
    case "$1" in native|usb) ;; *) return 2;; esac
    MW_SESSION_IP=; MW_SESSION_DEV=
    read -r MW_SESSION_IP MW_SESSION_DEV < "/etc/scut-multiwan/$1.session" || return 1
    [ "$MW_SESSION_IP" = none ] && [ "$MW_SESSION_DEV" = none ] && return 0
    mw_ipv4 "$MW_SESSION_IP" || return 1
    case "$1:$MW_SESSION_DEV" in
        native:phy0-sta*|native:phy2-sta*|usb:phy3-sta*|usb:mtusb*) return 0;;
    esac
    return 1
}

mw_prepare_login() {
    local slot dev ip previous
    slot="$1"; dev="$2"; ip="$3"
    mw_session_read "$slot" || {
        logger -t campus-portal "missing/invalid $slot session ledger; login refused"
        return 75
    }
    previous="$MW_SESSION_IP"
    if [ "$previous" != none ]; then
        case "$slot" in
            native) /usr/bin/campus-portal-logout "$dev" "$previous" || return $?;;
            usb) /usr/bin/campus-usb-logout "$dev" "$previous" || return $?;;
        esac
    fi
    mw_require_active 20 || return $?
    mw_session_write "$slot" "$ip" "$dev"
}

mw_session_clear() {
    mw_session_read "$1" || return 1
    # Releasing an untracked loser must not erase the winner's ledger.
    if [ "$MW_SESSION_IP" = "$2" ]; then
        mw_session_write "$1" none none
    fi
}
