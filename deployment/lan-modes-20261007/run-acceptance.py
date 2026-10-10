#!/usr/bin/env python3
"""Bounded three-mode check; always restore the user-selected wired mode."""
import datetime,json,subprocess,sys
from pathlib import Path
from zoneinfo import ZoneInfo
root=Path(__file__).resolve().parents[2]
ssh=['ssh','-S','/private/tmp/scut-goal-router5.sock','root@192.168.1.1']
results=[]
def run(argv):
    r=subprocess.run(argv,capture_output=True,text=True,timeout=35)
    return {'exit_code':r.returncode,'stdout':r.stdout.strip(),'stderr':r.stderr.strip()}
try:
    for mode in ['multi','tunnel','wired']:
        result={'mode':mode,'time':datetime.datetime.now(ZoneInfo('Asia/Singapore')).isoformat()}
        result['switch']=run(ssh+['/usr/bin/scut-lan-mode set '+mode])
        for name,script in [('physical_lan','lan-egress-check.py'),('explicit_1088','lan-proxy-check.py')]:
            probe=run([sys.executable,str(root/'tools'/script),'--label',mode])
            if probe['exit_code']==0:probe['result']=json.loads(probe['stdout'])
            result[name]=probe
        results.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
finally:
    final=run(ssh+['/usr/bin/scut-lan-mode set wired; /usr/bin/scut-lan-mode status'])
    print('FINAL '+json.dumps(final,ensure_ascii=False),flush=True)
    (root/'deployment/lan-modes-20261007/evidence/acceptance.json').write_text(json.dumps({'trials':results,'final_wired':final},indent=2,ensure_ascii=False)+'\n')
