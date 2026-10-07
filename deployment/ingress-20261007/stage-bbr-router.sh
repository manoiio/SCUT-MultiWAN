#!/bin/sh
set -eu
S=/tmp/scut-bbr50-20261007
test ! -e "$S"
mkdir "$S"; chmod 700 "$S"; umask 077
sed 's/58\.252\.223\.164:57501/58.252.223.164:57502/;s/192\.168\.1\.1:1088/192.168.1.1:1091/' /etc/scut-bond/client.json > "$S/client.json"
/usr/bin/scut-bond -config "$S/client.json" > "$S/client.log" 2>&1 &
p=$!; sleep 1
kill -0 "$p"
printf '%s %s\n' "$p" "$(awk '{print $22}' /proc/$p/stat)" > "$S/client.pid"
cat > "$S/cleanup.sh" <<'CLEAN'
#!/bin/sh
S=/tmp/scut-bbr50-20261007
read p st < "$S/client.pid"
if test -r "/proc/$p/stat" && test "$(awk '{print $22}' /proc/$p/stat)" = "$st"; then
 kill "$p"
fi
rm -f "$S/client.json"
CLEAN
chmod 700 "$S/cleanup.sh"
(sleep 840; "$S/cleanup.sh") >/dev/null 2>&1 &
