#!/bin/sh
set -eu
PUBLIC=58.252.223.164
case "${1:-}" in
 start)
  all=$(ip mptcp endpoint show)
  current=$(printf '%s\n' "$all" | awk '{for(i=2;i<NF;i++)if($i=="id"&&$(i+1)==214)print}')
  test -z "$current"
  # The public address is DNATed, not assigned locally. Inherit the listener
  # port; an explicit port would try to bind a second socket to this address.
  ip mptcp endpoint add "$PUBLIC" id 214 signal
  ;;
 stop)
  all=$(ip mptcp endpoint show)
  current=$(printf '%s\n' "$all" | awk '{for(i=2;i<NF;i++)if($i=="id"&&$(i+1)==214)print $1}')
  [ "$current" != "$PUBLIC" ] || ip mptcp endpoint delete id 214
  current=$(printf '%s\n' "$all" | awk '{for(i=2;i<NF;i++)if($i=="id"&&$(i+1)==215)print $1}')
  [ "$current" != ::ffff:192.168.1.98 ] || ip mptcp endpoint delete id 215
  ;;
 *) exit 2;;
esac
