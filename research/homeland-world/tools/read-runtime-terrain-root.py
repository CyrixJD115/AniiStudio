#!/usr/bin/env python3
"""Read the observed streamed terrain root, retaining unknown markers/flags."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('terrain_root_reader', Path(__file__).with_name('read-vegetation-storage.py'))
reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)


def decode(data):
    r = reader.Reader(data)
    sector_count, depth, height_scale = r.count(64), r.count(16), r.number('f')
    arrays = {}
    for name, width in [('tilingParams',1), ('averageColor',4), ('wetAlbedo',4), ('wetRoughness',1), ('wetNormal',1), ('porosity',4)]:
        count = r.count(1024)
        arrays[name] = [r.floats(width) if width > 1 else r.number('f') for _ in range(count)]
    layers = r.count(128)
    def descriptor():
        width, height, format, flags = r.number('H'), r.number('H'), r.number('B'), r.number('B')
        if not 0 < width <= 4096 or not 0 < height <= 4096: raise ValueError('Invalid terrain descriptor dimensions')
        return dict(width=width, height=height, format=format, packedFlagsU8=flags)
    diffuse, normal = descriptor(), descriptor()
    zipped = r.boolean(); marker = r.number('B'); indices = list(r.take(r.count(65536)))
    sectors = [r.number('I') for _ in range(r.count(4096))]
    valid = list(r.take(r.count(4096)))
    default, streaming = r.number('I'), r.number('I')
    descriptions = {name: descriptor() for name in ['height','normal','index','weight','tint','wetness','hole','atlasDiffuse','atlasNormal','apex','cone']}
    tail = r.number('B')
    if r.pos != len(data): raise ValueError('Unparsed terrain root bytes')
    if layers != len(arrays['averageColor']) or any(i >= layers for i in indices) or default >= layers:
        raise ValueError('Runtime layer table disagreement')
    if len(sectors) != sector_count**2 or not layers or not sector_count or not depth: raise ValueError('Invalid runtime sector/layer count')
    spans = []
    for packed in sectors:
        count, offset = packed & 255, packed >> 8
        if offset+count > len(indices): raise ValueError('Sector layer span out of bounds')
        spans.append({'packed': packed, 'offset': offset, 'count': count, 'layerIndices': indices[offset:offset+count]})
    return {'schema': 'original-runtime-terrain-root-v1', 'sectorCount': sector_count, 'quadTreeDepth': depth, 'heightMapScale': height_scale,
            **arrays, 'layerCount': layers, 'diffuseDescriptor': diffuse, 'normalDescriptor': normal, 'enableLayerZip': zipped,
            'opaqueIndexArrayMarkerU8': marker, 'layerIndexList': indices, 'sectorLayerSpans': spans,
            'opaqueValidLayerMaskBytes': valid, 'defaultLayer': default, 'streamingBufferLength': streaming,
            'descriptors': descriptions, 'opaqueTailU8': tail, 'bytesConsumed': r.pos,
            'decodedSHA256': hashlib.sha256(data).hexdigest(),
            'scope': 'Observed streamed root structure and bounded layer spans. Sector coordinate ordering, map weights, layer/height shader blending still unverified.'}


if __name__ == '__main__':
    source, output = map(Path, sys.argv[1:3]); result = decode(source.read_bytes())
    output.write_text(json.dumps(result, indent=2)+'\n')
    print('Read actual runtime terrain root:', result['layerCount'], 'layers,', len(result['sectorLayerSpans']), 'sector layer spans;', result['bytesConsumed'], 'bytes fully consumed')
