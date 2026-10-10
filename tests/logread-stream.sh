#!/bin/sh
# Run only in /tmp with a separately compiled fixture backend. No logd writes.
set -eu
cd /tmp/scut-logread-tests-20261010
helper=./scut-logread-fixture
rm -f view view.old view.raw view.raw.old pid args backend.pid
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > /tmp/scut-logread-tests-20261010/args\ncat /tmp/scut-logread-tests-20261010/input\n' > backend
chmod 700 backend
awk 'BEGIN {for(i=1;i<=100;i++) print "Sat Oct 10 13:00:01 2026 cron.err crond[2]: USER root pid 111 cmd /usr/bin/watchdog"; print "Sat Oct 10 13:00:02 2026 kern.err kernel: persistent-test I/O error"}' > input
"$helper" -l 101 -F view -S 1 -p pid
test ! -e pid
grep -q '^-l 101$' args
grep -q 'cron.info' view.old
grep -q 'cron.err' view.raw.old
grep -q 'kern.err.*I/O error' view
grep -q 'kern.err.*I/O error' view.raw
test "$(ls -l view | cut -c1-10)" = -rw-------
test "$(wc -c < view.old)" -le 1200
test "$(wc -c < view.raw.old)" -le 1200
"$helper" --raw -l 101 > raw-output
cmp raw-output input
"$helper" -l 101 > normal-output
grep -q cron.info normal-output
grep -q 'kern.err.*I/O error' normal-output
"$helper" -r localhost 514 > remote-output
cmp remote-output input
grep -q '^-r localhost 514$' args
"$helper" -F broken/path >/dev/null 2> write-error && exit 1
grep -q 'stream/write failed' write-error
printf '#!/bin/sh\necho $$ > /tmp/scut-logread-tests-20261010/backend.pid\nexec /bin/sleep 30\n' > backend
"$helper" -f -F view -p pid & wrapper=$!
i=0
while [ ! -s backend.pid ] || [ ! -s pid ]; do
    i=$((i+1)); test "$i" -lt 8; sleep 1
done
test "$(cat pid)" = "$wrapper"
backend_pid="$(cat backend.pid)"
kill -TERM "$wrapper"
wait "$wrapper"
test ! -e pid
! kill -0 "$backend_pid" 2>/dev/null
echo 'ALL 18 LOGREAD STREAM CHECKS PASSED (rotation/raw/filter/remote/error/signal)'
