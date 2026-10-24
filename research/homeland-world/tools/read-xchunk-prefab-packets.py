#!/usr/bin/env python3
"""Read observed static prefab packet records, preserving opaque flags and poses."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('prefab_reader', Path(__file__).with_name('read-vegetation-storage.py'))
reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)


def packet(data, resource_count):
    r = reader.Reader(data)
    directory_bytes = r.count(16384)
    if directory_bytes % 4: raise ValueError('Resource directory must divide by4')
    resources = [r.number('I') for _ in range(directory_bytes//4)]
    if len(set(resources)) != len(resources) or any(i >= resource_count for i in resources):
        raise ValueError('Invalid packet resource directory')
    count = r.count(65536)
    if len(data)-r.pos != count*46: raise ValueError('Observed prefab record stride differs')
    instances = []
    for ordinal in range(count):
        offset = r.pos; prefix = r.number('B')
        p, q, s = r.floats(3), r.floats(4), r.floats(3)
        suffix = r.number('B'); identity = r.number('I')
        if identity not in resources or abs(sum(v*v for v in q)-1) > 1e-4 or any(v == 0 for v in s):
            raise ValueError('Invalid original prefab resource/affine transform')
        instances.append({'ordinal': ordinal, 'resourceIndex': identity, 'position': p, 'rotationXYZW': q, 'scale': s,
                          'opaquePrefixU8': prefix, 'opaqueSuffixU8': suffix, 'encodedHex': data[offset:r.pos].hex()})
    if set(resources) != {i['resourceIndex'] for i in instances} or r.pos != len(data):
        raise ValueError('Prefab resource coverage/trailing bytes mismatch')
    return {'resourceIndices': resources, 'instances': instances, 'bytesConsumed': r.pos}


if __name__ == '__main__':
    storage_path, packets, output = map(Path, sys.argv[1:4])
    storage = json.loads(storage_path.read_text()); manifest = json.loads((packets/'manifest.json').read_text())
    if {r['id'] for r in manifest['records']} != set(storage['packetIDs']): raise ValueError('Packet directory differs from storage')
    result = {'schema': 'original-xchunk-prefab-placements-v1', 'storageSHA256': hashlib.sha256(storage_path.read_bytes()).hexdigest(),
              'originalPacketSourceSHA256': manifest['sourceSHA256'], 'packets': [],
              'scope': 'Static world prefabs only; two byte flags opaque. No stable player ownership IDs, no save data, no deduplication by pose'}
    for record in manifest['records']:
        data = (packets/record['file']).read_bytes()
        if hashlib.sha256(data).hexdigest() != record['sha256']: raise ValueError('Preserved packet changed')
        decoded = packet(data, len(storage['resources']))
        for instance in decoded['instances']: instance['assetPath'] = storage['resources'][instance['resourceIndex']]['path']
        result['packets'].append({'packetID': record['id'], 'decodedSHA256': record['sha256'], **decoded})
    output.write_text(json.dumps(result, indent=2)+'\n')
    print('Read', sum(len(p['instances']) for p in result['packets']), 'original static prefab records across', len(result['packets']), 'fully consumed packets')
