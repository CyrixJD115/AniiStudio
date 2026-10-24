#!/usr/bin/env python3
"""Follow actual water prefab m_PlatformData PPtrs without scanning unrelated CABs."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, research, output = map(Path, sys.argv[1:4])
directory = json.loads((research/'unity-bundle-directory-index.json').read_text())
lookup = {f['name'].lower(): b['bundle'] for b in directory['bundles'] for f in b['files']}
prefabs = json.loads((research/'homeland-original-water-prefabs.json').read_text())['prefabs']
targets = []
for prefab in prefabs:
    refs = [c['data']['m_PlatformData'] for c in prefab['root']['components'] if 'm_PlatformData' in c['data']]
    if len(refs) != 1: raise ValueError('Expected one explicit water platform pointer')
    pointer = refs[0]
    cab = prefab['externalFiles'][pointer['m_FileID']-1].split('/')[-1] if pointer['m_FileID'] else prefab['sourceCAB']
    targets.append((prefab['assetPath'], cab, pointer['m_PathID'], lookup[cab.lower()]))
result = {'scope': 'Original water platform metadata; shader/geometry/world fidelity still separate', 'platforms': []}
for name in sorted({t[3] for t in targets}):
    path = root/name; stat = path.stat(); digest = hashlib.sha256(path.read_bytes()).hexdigest()
    environment = UnityPy.load(str(path)); objects = {(o.assets_file.name.lower(), o.path_id): o for o in environment.objects}
    for prefab, cab, identity, bundle in targets:
        if bundle != name: continue
        obj = objects[(cab.lower(), identity)]
        if obj.type.name != 'MonoBehaviour': raise ValueError('Expected water platform metadata')
        data = obj.read_typetree()
        result['platforms'].append({'prefabPath': prefab, 'sourceBundle': name, 'sourceSHA256': digest, 'sourceCAB': cab,
                                    'pathID': identity, 'externalFiles': [e.path for e in obj.assets_file.externals], 'data': data})
        print('Read original water platform', data.get('m_Name'), flush=True)
    if (path.stat().st_size, path.stat().st_mtime_ns) != (stat.st_size, stat.st_mtime_ns): raise ValueError('Source changed while reading')
output.write_text(json.dumps(result, indent=2)+'\n')
