import subprocess,time,json,sys
from pathlib import Path
base=Path('/private/tmp/scut-ipv6-20261007')
a=[]
start=time.monotonic()
for label,port in [('old6-pair',1089),('alternate6-pair',1090)]:
 f=(base/(label+'.log')).open('w')
 a.append((subprocess.Popen([sys.executable,str(base/'receive.py'),'134217728',label,str(port)],stdout=f,stderr=subprocess.STDOUT),f,label))
for p,f,label in a:
 rc=p.wait();f.close();assert rc==0,(label,rc)
results=[]
for _,_,label in a:
 line=[s for s in (base/(label+'.log')).read_text().splitlines() if s.startswith('RESULT ')][-1]
 results.append(json.loads(line[7:]))
seconds=max(r['wall_end'] for r in results)-min(r['wall_start'] for r in results)
assert all(r['complete'] and r['payload_ok'] for r in results)
print(json.dumps(dict(results=results,common_wall_seconds=seconds,total_bytes=sum(r['bytes'] for r in results),aggregate_mbps=sum(r['bytes'] for r in results)*8/seconds/1e6)))
