#!/usr/bin/env python3
"""One bounded CDN TCP request; URL/UA only from private files, no payload cache."""
import argparse
import hashlib
import http.client
import json
import socket
import ssl
import threading
import time
import urllib.parse
from collections import deque
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--url-file', type=Path, required=True)
    p.add_argument('--ua-file', type=Path, required=True)
    p.add_argument('--proxy-port', type=int, default=1089)
    p.add_argument('--cdn-ip', default='120.222.194.36')
    p.add_argument('--bytes', type=int, required=True)
    p.add_argument('--label', required=True)
    p.add_argument('--sha256')
    p.add_argument('--prefix-bytes', type=int, default=0)
    p.add_argument('--repeat', type=int, default=1)
    p.add_argument('--max-total-bytes', type=int)
    p.add_argument('--max-seconds', type=float, default=75)
    a = p.parse_args()
    total_limit = a.max_total_bytes if a.max_total_bytes is not None else a.bytes
    if not 1 <= a.repeat <= 8 or a.bytes*a.repeat > total_limit or not 0 < a.max_seconds <= 180:
        p.error('repeat requires a sufficient explicit total byte limit')
    u = urllib.parse.urlsplit(a.url_file.read_text().strip())
    ua = a.ua_file.read_text().strip()
    if (u.scheme != 'https' or not u.hostname or a.bytes <= 0 or
            not 0 <= a.prefix_bytes <= a.bytes or any(x in ua for x in '\r\n')):
        p.error('invalid private input or byte limit')
    s = socket.socket()
    s.settimeout(20)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
    # macOS IP_BOUND_IF: do not accidentally test a separate utun path.
    s.setsockopt(socket.IPPROTO_IP, 25, socket.if_nametoindex('en0'))
    started = time.monotonic()
    count = 0
    deadline_hit = threading.Event()
    deadline_timer = None
    try:
        s.connect(('192.168.1.1', a.proxy_port))
        target = f'{a.cdn_ip}:443'
        s.sendall(f'CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n'.encode())
        header = bytearray()
        while not header.endswith(b'\r\n\r\n') and len(header) < 8192:
            b = s.recv(1)
            if not b:
                raise ValueError('incomplete CONNECT response')
            header.extend(b)
        if not header.startswith(b'HTTP/1.1 200 ') or not header.endswith(b'\r\n\r\n'):
            raise ValueError('CONNECT rejected')
        ctx = ssl.create_default_context()
        ctx.set_alpn_protocols(['http/1.1'])
        s = ctx.wrap_socket(s, server_hostname=u.hostname)
        def expire():
            deadline_hit.set()
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        # A read() can perform many individual receives. An independent shutdown
        # enforces an elapsed-time deadline even when each receive keeps making
        # slow progress and therefore never reaches its own socket timeout.
        deadline_timer = threading.Timer(max(0, a.max_seconds-(time.monotonic()-started)), expire)
        deadline_timer.daemon = True
        deadline_timer.start()
        path = urllib.parse.urlunsplit(('', '', u.path or '/', u.query, ''))
        digest = hashlib.sha256()
        prefix_digest = hashlib.sha256()
        checksums = []
        window = deque()
        minimum_window = None
        first = last = 0
        lastcount = 0
        for request_index in range(a.repeat):
            connection = 'close' if request_index == a.repeat-1 else 'keep-alive'
            s.sendall((f'GET {path} HTTP/1.1\r\nHost: {u.hostname}\r\n'
                       f'User-Agent: {ua}\r\nRange: bytes=0-{a.bytes-1}\r\n'
                       f'Accept-Encoding: identity\r\nConnection: {connection}\r\n\r\n').encode())
            r = http.client.HTTPResponse(s)
            r.begin()
            if not first:
                first = last = time.monotonic()
                window.append((first, 0))
            if r.status != 206 or int(r.getheader('Content-Length', '-1')) != a.bytes:
                raise ValueError('unexpected status/length')
            if not r.getheader('Content-Range', '').startswith(f'bytes 0-{a.bytes-1}/'):
                raise ValueError('unexpected range')
            file_count = 0
            file_digest = hashlib.sha256()
            while file_count < a.bytes:
                remaining_seconds = a.max_seconds-(time.monotonic()-started)
                if remaining_seconds <= 0:
                    raise TimeoutError('bounded transfer deadline')
                s.settimeout(min(20, remaining_seconds))
                b = r.read(min(131072, a.bytes-file_count))
                if not b:
                    break
                digest.update(b)
                file_digest.update(b)
                if count < a.prefix_bytes:
                    prefix_digest.update(b[:min(len(b), a.prefix_bytes-count)])
                file_count += len(b)
                count += len(b)
                now = time.monotonic()
                window.append((now, count))
                while len(window) > 2 and window[1][0] <= now-5:
                    window.popleft()
                span = now-window[0][0]
                if span >= 5:
                    speed = (count-window[0][1])*8/span/1e6
                    if minimum_window is None or speed < minimum_window['mbps']:
                        minimum_window = dict(mbps=speed, seconds=span,
                                              ending_at=now-started)
                if now-last >= 1:
                    print(json.dumps(dict(label=a.label, seconds=now-started, bytes=count,
                                          mbps=(count-lastcount)*8/(now-last)/1e6)), flush=True)
                    last, lastcount = now, count
            file_checksum = file_digest.hexdigest()
            expected = a.sha256 or (checksums[0] if checksums else file_checksum)
            if file_count != a.bytes or file_checksum != expected:
                raise ValueError('incomplete or checksum mismatch')
            checksums.append(file_checksum)
            if request_index < a.repeat-1 and r.will_close:
                raise ValueError('origin does not support connection reuse')
            r.close()
        elapsed = time.monotonic()-started
        checksum = digest.hexdigest()
        if count != a.bytes*a.repeat:
            raise ValueError('incomplete or checksum mismatch')
        print('RESULT '+json.dumps(dict(label=a.label, bytes=count, seconds=elapsed,
              mbps=count*8/elapsed/1e6, ttfb=first-started,
              body_seconds=elapsed-(first-started),
              body_mbps=count*8/(elapsed-(first-started))/1e6,
              window_scope="after_response_headers", sha256=checksum,
              http_status=r.status, cdn_ip=a.cdn_ip, openssl=ssl.OPENSSL_VERSION,
              requests=a.repeat, per_request_sha256=checksums,
              minimum_five_second_window=minimum_window)), flush=True)
        if a.prefix_bytes:
            print('PREFIX '+json.dumps(dict(bytes=a.prefix_bytes,
                  sha256=prefix_digest.hexdigest())), flush=True)
        return 0
    except Exception as e:
        # Never echo exception strings that could include URL or headers.
        print('ERROR '+json.dumps(dict(label=a.label, bytes=count, seconds=time.monotonic()-started,
                                      error='TimeoutError' if deadline_hit.is_set() else type(e).__name__, minimum_five_second_window=minimum_window if 'minimum_window' in locals() else None)), flush=True)
        return 1
    finally:
        if deadline_timer is not None:
            deadline_timer.cancel()
        s.close()


if __name__ == '__main__':
    raise SystemExit(main())
