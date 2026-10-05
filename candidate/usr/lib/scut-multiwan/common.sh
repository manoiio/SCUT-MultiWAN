#!/bin/sh
# Shared BusyBox ash helpers. Locks are stable files: never unlink them.

mw_quiet_now() {
    local clock h m s
    clock="$(date '+%H %M %S')" || return 0
    read -r h m s <<EOF
$clock
EOF
    h="${h#0}"; m="${m#0}"; s="${s#0}"
    MW_SECONDS=$((h * 3600 + m * 60 + s))
    [ "$MW_SECONDS" -ge 360 ] && [ "$MW_SECONDS" -lt 27000 ]
}

# 76 means deferred by the quiet period (including a bounded-operation margin).
mw_require_active() {
    [ ! -e /tmp/scut-multiwan-deploying ] || return 75
    mw_quiet_now && return 76
    if [ "$MW_SECONDS" -lt 360 ] &&
       [ $((360 - MW_SECONDS)) -le "${1:-30}" ]; then
        return 76
    fi
    return 0
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
    local path waited limit
    path=/tmp/scut-multiwan-locks/portal
    if [ "$(readlink /proc/self/fd/9 2>/dev/null)" = "$path" ]; then
        flock -n 9 || return 75
        return 0
    fi
    (umask 077; mkdir -p /tmp/scut-multiwan-locks) || return 1
    chmod 700 /tmp/scut-multiwan-locks || return 1
    exec 9>>"$path" || return 1
    waited=0; limit="${1:-30}"
    while ! flock -n 9; do
        mw_require_active || return $?
        [ "$waited" -lt "$limit" ] || return 75
        sleep 1
        waited=$((waited + 1))
    done
    mw_require_active
}

mw_online() {
    local code
    mw_require_active $((${2:-8} + 2)) || return $?
    code="$(curl -4 --interface "$1" --silent --fail --head \
        --max-time "${2:-8}" --output /dev/null --write-out '%{http_code}' \
        https://www.baidu.com/ 2>/dev/null)" || return 1
    [ "$code" = 200 ]
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
