import socket,http.client,time,json,hashlib,sys
n=int(sys.argv[1]);label=sys.argv[2];port=int(sys.argv[3]) if len(sys.argv)>3 else 1089
s=socket.socket();s.settimeout(20);s.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1<<20);s.setsockopt(socket.IPPROTO_IP,25,socket.if_nametoindex('en0'));wall_start=time.time();start=time.monotonic();s.connect(('192.168.1.1',port));s.sendall(f'GET /__scut_benchmark/{n} HTTP/1.1\r\nHost: 192.168.1.1\r\nConnection: close\r\n\r\n'.encode());r=http.client.HTTPResponse(s);r.begin();first=time.monotonic();assert r.status==200,(r.status,r.read(1024));assert int(r.getheader('Content-Length'))==n
pattern=bytes(range(256))*512;count=0;h=hashlib.sha256();last=first;lastcount=0;valid=True
while count<n:
 b=r.read(min(131072,n-count))
 if not b:break
 valid=valid and b==pattern[:len(b)];h.update(b);count+=len(b);now=time.monotonic()
 if now-last>=1:
  print(json.dumps(dict(label=label,seconds=now-start,bytes=count,mbps=(count-lastcount)*8/(now-last)/1e6)),flush=True);last=now;lastcount=count
end=time.monotonic();s.close();print('RESULT '+json.dumps(dict(label=label,wall_start=wall_start,wall_end=time.time(),bytes=count,complete=count==n,payload_ok=valid,seconds=end-start,ttfb=first-start,mbps=count*8/(end-start)/1e6,sha256=h.hexdigest())),flush=True)
