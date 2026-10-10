#!/usr/bin/env python3
"""Small physical-LAN TCP/TLS and UDP DNS checks; no proxy or bulk download."""
import argparse, json, socket, ssl, struct, time
p=argparse.ArgumentParser(); p.add_argument('--label',required=True); a=p.parse_args()
def bound(kind):
    s=socket.socket(socket.AF_INET,kind); s.settimeout(8)
    s.setsockopt(socket.IPPROTO_IP,25,socket.if_nametoindex('en0'))
    return s
out={'label':a.label,'physical_interface':'en0'}
s=bound(socket.SOCK_STREAM); s.connect(('183.232.239.18',443))
with ssl.create_default_context().wrap_socket(s,server_hostname='www.bilibili.com') as t:
    t.sendall(b'HEAD / HTTP/1.1\r\nHost: www.bilibili.com\r\nConnection: close\r\n\r\n')
    data=b''
    while len(data)<16384:
        b=t.recv(4096)
        if not b:break
        data+=b
    out['tls_http_status']=data.split(b'\r\n',1)[0].decode()
with bound(socket.SOCK_STREAM) as s:
    s.connect(('120.226.74.152',80));s.sendall(b'GET / HTTP/1.1\r\nHost: myip.ipip.net\r\nConnection: close\r\n\r\n')
    data=b''
    while len(data)<16384:
        b=s.recv(4096)
        if not b:break
        data+=b
    import re
    out['observed_exit_ipv4']=re.search(rb'IP[^0-9]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)',data).group(1).decode()
query=struct.pack('!HHHHHH',0x5375,0x0100,1,0,0,0)+b'\x07example\x03com\x00'+struct.pack('!HH',1,1)
for server in ['1.1.1.1','192.168.1.1']:
    with bound(socket.SOCK_DGRAM) as s:
        start=time.monotonic();s.sendto(query,(server,53));data,peer=s.recvfrom(4096)
        ident,flags,questions,answers=struct.unpack('!HHHH',data[:8])
        out['udp_dns_'+server]={'id_matches':ident==0x5375,'rcode':flags&15,'answers':answers,'seconds':round(time.monotonic()-start,3),'reply_peer':peer[0]}
print(json.dumps(out))
