#!/usr/bin/env python3
"""Bounded reader for observed XChunkV2 storage tables; metadata stays opaque.

Reads exact resource paths and packet IDs. Does not interpret collider packet
transforms, treat colliders as render meshes, or modify game/player data.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('storage_reader', Path(__file__).with_name('read-vegetation-storage.py'))
reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)


def storage(data):
    r = reader.Reader(data)
    pack = r.string()
    if '..' in pack.split('/') or not pack.startswith('xrenderPC/RuntimeLevel_FB_Home_01/XChunkV2/') or not pack.endswith('.pack'):
        raise ValueError('Unexpected XChunk packet path')
    header = [r.number('I') for _ in range(11)]
    byte_count = r.count(65536 * 4)
    if byte_count % 4:
        raise ValueError('Packet directory byte count must divide by4')
    packets = [r.number('I') for _ in range(byte_count // 4)]
    if len(set(packets)) != len(packets):
        raise ValueError('Duplicate packet IDs')
    resources = []
    for identity in range(r.count(4096)):
        offset = r.pos
        flags = r.number('H'); path = r.string(); tag = r.number('I')
        if not path.startswith('Assets/') or '..' in path.split('/') or not path.endswith(('.asset', '.prefab')):
            raise ValueError('Invalid original asset path')
        resources.append({'id': identity, 'offset': offset, 'opaquePrefixU16': flags, 'path': path, 'opaqueKindU32': tag})
    if r.pos != len(data):
        raise ValueError('Unparsed XChunk storage bytes')
    return {'schema': 'original-xchunk-storage-v1', 'packPath': pack, 'opaqueHeaderWords': header,
            'packetIDs': packets, 'resources': resources, 'bytesConsumed': r.pos,
            'decodedSHA256': hashlib.sha256(data).hexdigest(),
            'scope': 'Exact observed table structure only; header/resource tags and packet payload semantics remain opaque'}


if __name__ == '__main__':
    source, output = map(Path, sys.argv[1:3])
    result = storage(source.read_bytes())
    output.write_text(json.dumps(result, indent=2)+'\n')
    print('Read', len(result['resources']), 'explicit resources and', len(result['packetIDs']), 'packet IDs;', result['bytesConsumed'], 'bytes fully consumed')
