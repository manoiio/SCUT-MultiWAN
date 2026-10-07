#!/usr/bin/env python3
"""One HTTP request through the LAN proxy; signed URLs stay out of argv/logs."""
import argparse
import hashlib
import json
import pathlib
import ssl
import sys
import time
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("redirect requires a fresh direct URL")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url-file", type=pathlib.Path, required=True)
    p.add_argument("--user-agent-file", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    p.add_argument("--proxy", default="http://192.168.1.1:1088")
    p.add_argument("--max-bytes", type=int, required=True)
    p.add_argument("--range-bytes", type=int)
    a = p.parse_args()
    if a.max_bytes <= 0 or (a.range_bytes is not None and not 0 < a.range_bytes <= a.max_bytes):
        p.error("byte limits must be positive; range must fit max-bytes")
    if a.output.exists():
        p.error("output already exists")
    url = a.url_file.read_text().strip()
    ua = a.user_agent_file.read_text().strip()
    if urllib.parse.urlsplit(url).scheme not in ("http", "https") or "\n" in url or "\r" in url:
        p.error("URL file must contain one HTTP(S) URL")
    if not ua or "\n" in ua or "\r" in ua:
        p.error("User-Agent file must contain one header value")
    headers = {"User-Agent": ua, "Accept-Encoding": "identity"}
    if a.range_bytes:
        headers["Range"] = f"bytes=0-{a.range_bytes - 1}"
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": a.proxy, "https": a.proxy}),
        urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        NoRedirect(),
    )
    partial = a.output.with_name(a.output.name + ".part")
    started = time.monotonic()
    count = 0
    digest = hashlib.sha256()
    try:
        with opener.open(urllib.request.Request(url, headers=headers), timeout=30) as r:
            if r.status != (206 if a.range_bytes else 200):
                raise ValueError("unexpected HTTP status")
            length = r.headers.get("Content-Length")
            length = int(length) if length is not None else None
            if length is not None and (length < 0 or length > a.max_bytes):
                raise ValueError("response exceeds byte limit")
            if a.range_bytes and (length != a.range_bytes or not r.headers.get("Content-Range", "").startswith(f"bytes 0-{a.range_bytes - 1}/")):
                raise ValueError("range was not honored")
            with partial.open("xb") as f:
                while count < a.max_bytes:
                    chunk = r.read(min(131072, a.max_bytes - count))
                    if not chunk:
                        break
                    count += len(chunk)
                    f.write(chunk)
                    digest.update(chunk)
                if count == a.max_bytes and length != count:
                    raise ValueError("byte limit reached before proven completion")
            if length is not None and count != length:
                raise ValueError("incomplete response")
        partial.rename(a.output)
    except Exception as e:
        # Exception strings can contain the signed URL; report only the type.
        print(f"Download failed ({type(e).__name__}); partial file retained if created.", file=sys.stderr)
        return 1
    seconds = time.monotonic() - started
    print(json.dumps({"bytes": count, "seconds": round(seconds, 3), "Mbps": round(count * 8 / seconds / 1e6, 3), "sha256": digest.hexdigest()}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
