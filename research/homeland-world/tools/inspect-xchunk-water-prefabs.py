#!/usr/bin/env python3
"""Preserve the two explicitly referenced original Homeland water hierarchies."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, research, output = map(Path, sys.argv[1:4])
references = json.loads((research/'homeland-world-reference-links.json').read_text())['XChunkReference']
table = json.loads((research/'homeland-xchunk-prefab-storage.json').read_text())
wanted = {r['path'] for r in table['resources'] if '/EPrefab_Water' in r['path']}
indexed = {}
for path in (research/'environment-asset-index').glob('*.json'):
    index = json.loads(path.read_text())
    for asset in index['assets']:
        indexed[(asset['cab'].lower(), asset['pathID'])] = (asset, index)
targets = []
for pointer in references['data']['m_References']:
    cab = references['externalFiles'][pointer['m_FileID']-1].split('/')[-1]
    asset, index = indexed[(cab.lower(), pointer['m_PathID'])]
    if asset['path'] in wanted:
        targets.append((cab, pointer['m_PathID'], asset['path'], index))
if {t[2] for t in targets} != wanted or len(targets) != 2:
    raise ValueError('Original water reference/path disagreement')
result = {'scope': 'Original static water prefab hierarchy only; no inferred world placements or shader port', 'prefabs': []}
for name in sorted({t[3]['bundle'] for t in targets}):
    source = root/name; stat = source.stat()
    expected = next(t[3]['sha256'] for t in targets if t[3]['bundle'] == name)
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != expected: raise ValueError('Indexed water source changed')
    environment = UnityPy.load(str(source))
    objects = {(o.assets_file.name.lower(), o.path_id): o for o in environment.objects}
    for cab, path_id, asset_path, index in targets:
        if index['bundle'] != name: continue
        visited = set()
        def game_object(identity, depth=0):
            if depth > 8 or len(visited) >= 256 or identity in visited:
                raise ValueError('Water hierarchy cyclic or exceeds bound')
            visited.add(identity)
            obj = objects[(cab.lower(), identity)]
            if obj.type.name != 'GameObject': raise ValueError('Expected original GameObject')
            data = obj.read_typetree()
            node = {'name': data['m_Name'], 'pathID': identity, 'components': [], 'children': []}
            for reference in data['m_Component']:
                pointer = reference['component']
                if pointer['m_FileID']: raise ValueError('Unexpected external water component')
                component = objects[(cab.lower(), pointer['m_PathID'])]
                tree = component.read_typetree()
                node['components'].append({'pathID': component.path_id, 'type': component.type.name, 'data': tree})
                if component.type.name == 'Transform':
                    for child in tree['m_Children']:
                        if child['m_FileID']: raise ValueError('Unexpected external child')
                        transform = objects[(cab.lower(), child['m_PathID'])].read_typetree()
                        node['children'].append(game_object(transform['m_GameObject']['m_PathID'], depth+1))
            return node
        hierarchy = game_object(path_id)
        file = objects[(cab.lower(), path_id)].assets_file
        result['prefabs'].append({'assetPath': asset_path, 'sourceBundle': name, 'sourceSHA256': digest,
                                 'sourceCAB': cab, 'pathID': path_id,
                                 'externalFiles': [e.path for e in file.externals], 'root': hierarchy})
        print('Preserved original water hierarchy', hierarchy['name'], len(visited), 'nodes', flush=True)
    if (source.stat().st_size, source.stat().st_mtime_ns) != (stat.st_size, stat.st_mtime_ns):
        raise ValueError('Water source changed while reading')
output.write_text(json.dumps(result, indent=2)+'\n')
