"""Loopback-only synthetic HTTP bodies for testing real curl size boundaries.

No credentials, Portal endpoints or production requests. Stop with Ctrl-C.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time

LIMIT = 1048576
PREFIX = b'dr1003({"result":1,"padding":"'


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass

    def do_GET(self):
        mode = self.path.lstrip('/')
        sizes = {'small': 1024, 'boundary': LIMIT, 'over': LIMIT + 1,
                 'chunked': LIMIT + 1, 'eof': LIMIT + 1,
                 'short': LIMIT, 'slow': LIMIT}
        if mode not in sizes:
            self.send_error(404)
            return
        body = PREFIX + b'x' * (sizes[mode] - len(PREFIX) - 4) + b'"});'
        self.send_response(200)
        if mode == 'chunked':
            self.send_header('Transfer-Encoding', 'chunked')
        elif mode != 'eof':
            self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True
        try:
            if mode in ('short', 'slow'):
                self.wfile.write(b'dr1003({"result":1});')
                self.wfile.flush()
                if mode == 'slow':
                    time.sleep(2)
            elif mode == 'chunked':
                for offset in range(0, len(body), 4096):
                    chunk = body[offset:offset + 4096]
                    self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                self.wfile.write(b'0\r\n\r\n')
            else:
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when curl aborts overflow/timeout fixtures.


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18784)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'fixture listening on 127.0.0.1:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
