#!/usr/bin/env python3
"""Fetch only exact missing prefab URLs observed in retained Aniidex manifests.

Never constructs guessed asset paths, alters capture records, or contacts game
servers. GLB identities remain linked to their existing source-layout manifest.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import urllib.parse
import urllib.request

parser=argparse.ArgumentParser()
parser.add_argument('coverage',type=Path)
parser.add_argument('cache',type=Path)
parser.add_argument('report',type=Path)
parser.add_argument('--download',action='store_true')
args=parser.parse_args()
missing={row['prefab'] for area in json.loads(args.coverage.read_text()) for row in area['missing']}
found={}
for manifest in sorted(args.cache.glob('*/manifest.json')):
    scene=json.loads(manifest.read_text())
    for prefab,path in scene.get('models',{}).items():
        if prefab not in missing or prefab in found:continue
        url=urllib.parse.urljoin('https://aniidex.com',path);parts=urllib.parse.urlparse(url)
        if parts.scheme!='https' or parts.hostname!='aniidex.com' or not parts.path.endswith('.glb'):continue
        filename=Path(parts.path).name
        if not filename or filename in ['.','..']:continue
        found[prefab]={'prefab':prefab,'sourceManifest':str(manifest),'url':url,
                       'destination':str(manifest.parent/filename)}
results=[]
for prefab,entry in sorted(found.items()):
    if args.download:
        try:
            request=urllib.request.Request(entry['url'],headers={'User-Agent':'Aniimo Atlas/2.0 (personal macOS companion)'})
            with urllib.request.urlopen(request,timeout=45) as response:
                if urllib.parse.urlparse(response.url).hostname!='aniidex.com':raise ValueError('Unexpected asset redirect')
                data=response.read(30*1024*1024+1)
            if len(data)>30*1024*1024 or len(data)<12:raise ValueError('Invalid GLB size')
            magic,version,size=struct.unpack_from('<4sII',data)
            if magic!=b'glTF' or version!=2 or size!=len(data):raise ValueError('Invalid GLB header/length')
            destination=Path(entry['destination']);temporary=destination.with_suffix('.download')
            temporary.write_bytes(data);temporary.replace(destination)
            entry.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),status='downloaded')
        except Exception as error:entry.update(status='failed',error=str(error))
    else:entry['status']='observed-source-only'
    results.append(entry)
report={'requested':len(missing),'observedSources':len(found),'assets':results,'unresolved':sorted(missing-found.keys())}
args.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'requested':len(missing),'observedSources':len(found),'downloaded':sum(a['status']=='downloaded' for a in results),
                  'failed':sum(a['status']=='failed' for a in results),'unresolved':report['unresolved']}))
