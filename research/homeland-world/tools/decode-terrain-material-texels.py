#!/usr/bin/env python3
"""Verified discrete material IDs/rotations/weight from original terrain bake CS.

R/B are layer IDs, G/A rotation bytes; weight R interpolates R-layer to B-layer.
Does not claim full stochastic UV, wetness, tint or height-aware filtering port.
"""
import hashlib
import json
import math
from pathlib import Path
import sys
import numpy as np


def texel(rgba, weight, layer_count):
    if len(rgba) != 4 or not all(isinstance(v, int) and 0 <= v <= 255 for v in rgba) or not isinstance(weight, int) or not 0 <= weight <= 255:
        raise ValueError('Expected original RGBA8 and R8 channels')
    if not 0 <= rgba[0] < layer_count or not 0 <= rgba[2] < layer_count: raise ValueError('Source layer ID out of range')
    return {'layer0': rgba[0], 'rotation0Byte': rgba[1], 'layer1': rgba[2], 'rotation1Byte': rgba[3], 'layer1Weight': weight/255}


def fast_rotation(byte):
    if not isinstance(byte, int) or not 0 <= byte <= 255: raise ValueError('Expected rotation byte')
    # Algebraic form of the source's parabolic sin(angle) approximation. The
    # shader uses float constants2pi/256 and1/(2pi); this is not bit-identical GPU math.
    def sine(turn):
        f = turn-math.floor(turn)
        return max(1-(4*f-1)**2, 0)-max(1-(4*f-3)**2, 0)
    return sine(byte/256+.25), sine(byte/256)


if __name__ == '__main__':
    research, output = map(Path, sys.argv[1:3])
    root = json.loads((research/'homeland-runtime-terrain-root.json').read_text())
    records = json.loads((research/'homeland-terrain-sector-records.json').read_text())
    shader_dir = research/'terrain-bake-shader-inspection'
    proof = json.loads((shader_dir/'manifest.json').read_text())['shaders'][0]
    kernel = proof['kernels'][0]; code = (shader_dir/kernel['file']).read_bytes()
    if hashlib.sha256(code).hexdigest() != kernel['sha256']: raise ValueError('Original bake program changed')
    bindings = {t['name']: t['bindPoint'] for t in kernel['metadata']['textures']}
    if bindings.get('_IndexTextureArray') != 0 or bindings.get('_WeightTextureArray') != 1: raise ValueError('Original shader resource binding changed')
    asm_path = shader_dir/Path(kernel['file']).with_suffix('.asm').name
    asm = asm_path.read_text()
    for snippet in ['gather4_indexable(texture2darray) r2.xyzw, r3.xyzx, t0.xyzw, s0.w',
                    'gather4_indexable(texture2darray) r15.xyzw, r3.xyzx, t0.xyzw, s0.y',
                    'gather4_indexable(texture2darray) r6.xyzw, r3.xyzx, t0.xyzw, s0.z',
                    'gather4_indexable(texture2darray) r18.xyzw, r3.xyzx, t0.xyzw, s0.x',
                    'gather4_indexable(texture2darray) r19.xyzw, r3.xyzx, t1.xyzw, s0.x',
                    'mad r0.xyzw, r19.w, r0.xyzw, r17.xyzw']:
        if snippet not in asm: raise ValueError('Shader proof excerpt differs; re-audit packing')
    minima = np.full(4, 255); maxima = np.zeros(4, dtype=int); count = 0; rows = []
    for record in records['records']:
        if record['level'] != 0: continue
        data = (research/record['recordFile']).read_bytes()
        if hashlib.sha256(data).hexdigest() != record['decodedSHA256']: raise ValueError('Original sector changed')
        def payload(role):
            meta = record['maps'][role]; return data[meta['offset']:meta['offset']+meta['bytes']]
        index = np.frombuffer(payload('index'), dtype=np.uint8).reshape(129,129,4)
        weight = np.frombuffer(payload('weight'), dtype=np.uint8).reshape(129,129)/255
        if np.max(index[:,:,[0,2]]) >= root['layerCount']: raise ValueError('Original layer exceeds runtime table')
        minima = np.minimum(minima, index.min(axis=(0,1))); maxima = np.maximum(maxima, index.max(axis=(0,1)))
        count += weight.size
        coverage = {}
        for layer in range(root['layerCount']):
            contribution = float(np.sum(np.where(index[:,:,0]==layer, 1-weight, 0)+np.where(index[:,:,2]==layer, weight, 0)))
            if contribution: coverage[str(layer)] = contribution/weight.size
        rows.append({'x': record['x'], 'z': record['z'], 'unfilteredMaterialContributions': coverage})
        if (record['x'], record['z']) == (8,5):
            # Exact source world[32,-135.5] falls at this sector sample.
            home = texel(index[113,64].tolist(), int(round(weight[113,64]*255)), root['layerCount'])
    report = {'schema': 'original-terrain-material-texels-v1', 'sectorCount': len(rows), 'texelCount': count,
              'originalShaderSHA256': proof['sourceSHA256'], 'programSHA256': kernel['sha256'], 'assemblySHA256': hashlib.sha256(asm_path.read_bytes()).hexdigest(),
              'channels': {'R':'layer0','G':'rotation0Byte','B':'layer1','A':'rotation1Byte','weightR':'layer1Weight'},
              'minimumChannels': minima.tolist(), 'maximumChannels': maxima.tolist(), 'homeCenterSourceTexel': home, 'sectors': rows,
              'scope': 'Exact discrete source IDs/rotation bytes and prefilter weight. Stochastic UV, four-neighbor height filtering, tint/wetness and normal decode remain separate.'}
    output.write_text(json.dumps(report, indent=2)+'\n')
    print('Verified', count, 'source material texels across', len(rows), 'sectors; home-center material', home)
