#!/usr/bin/env python3
"""Read original runtime terrain map payloads and cross-check independent heights.

Map offsets/channels retained without guessing index/weight shader packing.
Trailing sector metadata stays opaque rather than silently discarded.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import numpy as np

spec = importlib.util.spec_from_file_location('sector_reader', Path(__file__).with_name('read-vegetation-storage.py'))
reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)
ROLES = ['height','normal','index','weight','tint','wetness','hole','atlasDiffuse','atlasNormal','apex','cone']


def record(data, root):
    r = reader.Reader(data); level, x, z = [r.count(64) for _ in range(3)]
    grid = root['sectorCount'] >> level
    if level >= root['quadTreeDepth'] or x >= grid or z >= grid: raise ValueError('Invalid original terrain key')
    center, extents = r.floats(3), r.floats(3)
    edge = 64*(2**level)
    if center[0] != -512+(x+.5)*edge or center[2] != -512+(z+.5)*edge or extents[0] != edge/2 or extents[2] != edge/2:
        raise ValueError('Terrain position/extent differs from source grid')
    maps = {}
    for role in ROLES:
        d = dict(width=r.number('H'), height=r.number('H'), format=r.number('B'), packedFlagsU8=r.number('B'))
        if d != root['descriptors'][role]: raise ValueError('Terrain map descriptor differs from actual runtime root')
        name = r.string(); length = r.count(2*1024*1024); offset = r.pos; payload = r.take(length)
        w,h,f = d['width'],d['height'],d['format']
        expected = ((w+3)//4)*((h+3)//4)*16 if f == 25 else w*h*{4:4,9:2,63:1,20:16}[f]
        if length != expected: raise ValueError('Map payload byte length differs from descriptor')
        maps[role] = {**d, 'name': name, 'offset': offset, 'bytes': length, 'sha256': hashlib.sha256(payload).hexdigest()}
    tail = data[r.pos:]
    if len(tail) > 65536: raise ValueError('Uninterpreted terrain tail exceeds bound')
    return {'level': level, 'x': x, 'z': z, 'bounds': {'center': center, 'extents': extents},
            'maps': maps, 'interpretedBytes': r.pos, 'opaqueTailHex': tail.hex(), 'sourceBytes': len(data)}


if __name__ == '__main__':
    research, world, output = map(Path, sys.argv[1:4])
    root = json.loads((research/'homeland-runtime-terrain-root.json').read_text())
    source = json.loads((world/'sources.json').read_text()); heights = {}
    for tile in source['terrain']:
        data = (world/tile['file']).read_bytes()
        if hashlib.sha256(data).hexdigest() != tile['fileSHA256']: raise ValueError('Independent terrain height source changed')
        heights[(tile['x'],tile['z'])] = np.frombuffer(data, dtype='<u2').reshape(257,257)
    rows = []; seen = set(); mismatches = 0
    for folder in sorted(research.glob('terrain-sector-pack-*')):
        manifest = json.loads((folder/'manifest.json').read_text())
        for entry in manifest['records']:
            path = folder/entry['file']; data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != entry['sha256']: raise ValueError('Preserved sector changed')
            item = record(data, root); key = (item['level'],item['x'],item['z'])
            if key in seen: raise ValueError('Duplicate terrain level/sector identity')
            seen.add(key)
            # Coarse nodes retain their anchor in the finest sector grid.
            anchor_x, anchor_z = item['x'] << item['level'], item['z'] << item['level']
            morton = sum(((anchor_x>>i)&1)<<(2*i) | ((anchor_z>>i)&1)<<(2*i+1) for i in range(8))
            if entry['id'] != (item['level']<<28)|morton: raise ValueError('Packet ID differs from explicit sector coordinates')
            meta = item['maps']['height']; actual = np.frombuffer(data[meta['offset']:meta['offset']+meta['bytes']], dtype='<u2').reshape(129,129)
            # Source Unity tiles128m/257samples; runtime finest sectors64m/129.
            base_x, base_z = item['x']*128*(2**item['level']), item['z']*128*(2**item['level'])
            sample_step = 2**item['level']; differences = 0
            for row in range(129):
                gz = base_z+row*sample_step; tz = min(gz//256,7); iz = gz-tz*256
                for col in range(129):
                    gx = base_x+col*sample_step; tx = min(gx//256,7); ix = gx-tx*256
                    differences += int(actual[row,col] != heights[(tx,tz)][iz,ix])
            mismatches += differences
            rows.append({'packetID': entry['id'], 'recordFile': str(path.relative_to(research)), 'decodedSHA256': entry['sha256'],
                         **item, 'independentHeightMismatches': differences})
        print('Checked sector pack', folder.name, len(manifest['records']), 'records', flush=True)
    report = {'schema': 'original-terrain-sector-records-v1', 'records': rows, 'independentHeightMismatches': mismatches,
              'scope': 'Original map payload offsets and verified coordinates/heights. Packed material-index/weight shader semantics and trailing metadata still unknown.'}
    output.write_text(json.dumps(report, indent=2)+'\n')
    print('Read', len(rows), 'terrain records;', mismatches, 'height samples differ from independently recovered Unity terrain')
    if mismatches: raise ValueError('Streamed and source terrain heights disagree')
