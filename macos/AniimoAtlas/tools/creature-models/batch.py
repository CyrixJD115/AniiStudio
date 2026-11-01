import json,sys,traceback
from export_creature import *
ids=open('ids.txt').read().split();rp=OUT/'report.json'
rep=json.loads(rp.read_text()) if rp.exists() else {'models':{},'failures':{}}
for i,pid in enumerate(ids):
 if pid in rep['models']:continue
 try:rep['models'][pid]=export(pid);rep['failures'].pop(pid,None);print(i+1,len(ids),pid,'OK',rep['models'][pid]['bytes'],flush=True)
 except Exception:rep['failures'][pid]=traceback.format_exc(limit=4);print(i+1,pid,'FAIL',rep['failures'][pid][-300:],flush=True)
 rp.write_text(json.dumps(rep,indent=1))
print('DONE',len(rep['models']),len(rep['failures']))
