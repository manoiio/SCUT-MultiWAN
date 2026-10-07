#!/usr/bin/env python3
"""Bounded acceptance; change recovery only after execution has been approved."""
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--label', required=True)
p.add_argument('--recovery', type=int, choices=(1, 5), default=5)
a = p.parse_args()
if not a.label.replace('-', '').isalnum():
    p.error('invalid label')
root = Path(__file__).resolve().parents[2]
out = root / 'deployment/ingress-20261007/evidence' / (a.label + '.log')
if out.exists():
    p.error('refusing to overwrite evidence')
ssh = ['ssh', '-S', '/private/tmp/scut-goal-vps-via-hk4.sock', '-p', '57500', 'root@58.252.223.164']
unit = 'scut-rack-' + a.label

def remote(command):
    r = subprocess.run(ssh + [command], text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=25)
    print(r.stdout, end='', flush=True)
    return r

def receipt(command):
    r = remote(command)
    log.write(r.stdout)
    log.flush()
    if r.returncode:
        raise RuntimeError('remote operation failed')

with out.open('x') as log:
    log.write(json.dumps({'label': a.label, 'requested_recovery': a.recovery,
                          'started': datetime.now(timezone.utc).isoformat()}) + '\n')
    try:
        receipt('test "$(sysctl -n net.ipv4.tcp_recovery)" = 1 && '
                f'systemd-run --unit={unit}-restore --on-active=600s '
                '--timer-property=AccuracySec=1s /bin/sh -c "sysctl -w net.ipv4.tcp_recovery=1"')
        receipt(f'sysctl -w net.ipv4.tcp_recovery={a.recovery}; date -Iseconds; '
                'cat /proc/net/dev | grep ens18')
        receipt(f'systemd-run --unit={unit}-sample --property=RuntimeMaxSec=85 '
                '/bin/sh -c \'i=0; while [ "$i" -lt 75 ]; do date -Iseconds; '
                'sysctl -n net.ipv4.tcp_recovery; '
                'ss -nti "( sport = :57501 or dst 39.173.161.17 )"; ss -Mni; '
                f'sleep 1; i=$((i+1)); done > /tmp/{unit}-sample.log\'')
        args = [sys.executable, str(root / 'tools/bond-accept.py'),
                '--url-file', '/private/tmp/scut-mixed-20261007/bocchi-url.txt',
                '--ua-file', '/private/tmp/scut-mixed-20261007/ua.txt',
                '--proxy-port', '1088', '--cdn-ip', '39.173.161.17',
                '--bytes', '943718400', '--sha256',
                '663dbca8be7ee24256421ecc94b3f7fd363ebd45fd1cee7489679c78ed42d12b',
                '--label', a.label, '--max-seconds', '75']
        with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, cwd=root) as child:
            for line in child.stdout:
                print(line, end='', flush=True)
                log.write(line)
                log.flush()
            code = child.wait()
        receipt('date -Iseconds; sysctl net.ipv4.tcp_recovery; '
                'cat /proc/net/dev | grep ens18')
    finally:
        # Restore the live parameter directly; the original queue installer is
        # deliberately not used for rollback. Keep guard armed if SSH fails.
        r = remote('sysctl -w net.ipv4.tcp_recovery=1')
        log.write(r.stdout)
        log.flush()
        if r.returncode == 0:
            r = remote(f'systemctl stop {unit}-restore.timer {unit}-sample.service; '
                       'sysctl net.ipv4.tcp_recovery')
            log.write(r.stdout)
            log.flush()
        else:
            raise RuntimeError('restore not confirmed; remote guard remains armed')
sys.exit(code)
