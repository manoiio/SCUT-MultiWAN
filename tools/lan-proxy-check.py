#!/usr/bin/env python3
"""Check the explicit 1088 proxy with a small HTTP egress query."""
import argparse,json,re,socket
p=argparse.ArgumentParser();p.add_argument('--label',required=True);a=p.parse_args()
s=socket.socket();s.settimeout(10);s.setsockopt(socket.IPPROTO_IP,25,socket.if_nametoindex('en0'))
with s:
 s.connect(('192.168.1.1',1088));s.sendall(b'CONNECT 120.226.74.152:80 HTTP/1.1\r\nHost: 120.226.74.152:80\r\n\r\n')
 header=b''
 while not header.endswith(b'\r\n\r\n') and len(header)<4096:header+=s.recv(1)
 if not header.startswith(b'HTTP/1.1 200'):raise RuntimeError('CONNECT failed')
 s.sendall(b'GET / HTTP/1.1\r\nHost: myip.ipip.net\r\nConnection: close\r\n\r\n')
 data=b''
 while len(data)<16384:
  b=s.recv(4096)
  if not b:break
  data+=b
 match=re.search(rb'IP[^0-9]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)',data)
 if not match:raise RuntimeError('egress response unavailable')
 print(json.dumps({'label':a.label,'proxy':'192.168.1.1:1088','http_status':data.split(b'\r\n')[0].decode(),'observed_exit_ipv4':match.group(1).decode()}))
