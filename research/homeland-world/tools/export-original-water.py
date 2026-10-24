#!/usr/bin/env python3
"""Original water geometry and placements; explicitly static native color QA.

Uses the original _SurfaceOverlay0 swatch, not the original depth/refraction,
foam, absorption or animation shader. Never substitutes a generated water plane.
"""
from functools import lru_cache
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import sys
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

root, research, output = map(Path, sys.argv[1:4]); output.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('water_vertex', Path(__file__).with_name('decode-environment-vertices.py'))
codec = importlib.util.module_from_spec(spec); spec.loader.exec_module(codec)
indexes = {}
for path in (research/'environment-asset-index').glob('*.json'):
    index = json.loads(path.read_text())
    for asset in index['assets']: indexes.setdefault(asset['path'], []).append((asset, index))
platforms = json.loads((research/'homeland-water-platform-data.json').read_text())['platforms']
materials = {m['assetPath']: m for m in json.loads((research/'homeland-water-materials.json').read_text())['materials']}
storage = json.loads((research/'homeland-xchunk-prefab-storage.json').read_text())
source_placements = json.loads((research/'homeland-xchunk-prefab-placements.json').read_text())
hashes = {}


def verify(name, expected):
    if name not in hashes: hashes[name] = hashlib.sha256((root/name).read_bytes()).hexdigest()
    if hashes[name] != expected: raise ValueError('Original source checksum changed')


@lru_cache(maxsize=1)
def bundle(name):
    source = root/name; stat = source.stat(); environment = UnityPy.load(str(source))
    if (source.stat().st_size, source.stat().st_mtime_ns) != (stat.st_size, stat.st_mtime_ns): raise ValueError('Source changed during load')
    return {(o.assets_file.name.lower(), o.path_id): o for o in environment.objects}


models = []
for platform in platforms:
    verify(platform['sourceBundle'], platform['sourceSHA256'])
    renderers = platform['data']['m_DefaultConfig']['m_Lods'][0]['m_Renderers']
    if len(renderers) != 1 or len(renderers[0]['m_MaterialList']) != 1: raise ValueError('Unsupported water renderer layout')
    renderer = renderers[0]; mesh_path = renderer['m_MeshPath']['m_Path']
    candidates = indexes[mesh_path]
    if len(candidates) != 1: raise ValueError('Water mesh path ambiguous')
    asset, index = candidates[0]; verify(index['bundle'], index['sha256'])
    obj = bundle(index['bundle'])[(asset['cab'].lower(), asset['pathID'])]
    if obj.type.name != 'Mesh': raise ValueError('Expected original water mesh')
    mesh = obj.read(); handler = MeshHandler(mesh); handler.process()
    channels = mesh.m_VertexData.m_Channels
    compressed = channels[0].format == 8 and channels[0].dimension == 4
    positions = []; normals = []; uvs = []; original = []
    for p, n, uv in zip(handler.m_Vertices, handler.m_Normals, handler.m_UV0):
        if compressed: xyz, normal, texcoord = codec.decode(p, n, uv)
        elif channels[0].format == 0 and len(p) >= 3 and len(n) >= 3: xyz, normal, texcoord = list(p[:3]), list(n[:3]), list(uv[:2])
        else: raise ValueError('Unverified water vertex encoding')
        if not all(math.isfinite(v) for v in xyz+normal+texcoord): raise ValueError('Nonfinite geometry')
        original.append(xyz); positions.append([xyz[2], xyz[1], xyz[0]])
        normals.append([normal[2], normal[1], normal[0]]); uvs.append([texcoord[0], 1-texcoord[1]])
    if not positions or len(positions) != mesh.m_VertexData.m_VertexCount: raise ValueError('Incomplete water geometry')
    step = max(2*(1 << (3+((p[3] >> 1)&7)))/65535 for p in handler.m_Vertices) if compressed else .0001
    bounds = obj.read_typetree()['m_LocalAABB']; errors = []
    for axis, key in enumerate('xyz'):
        low = min(p[axis] for p in original); high = max(p[axis] for p in original)
        errors += [abs((low+high)/2-bounds['m_Center'][key]), abs((high-low)/2-bounds['m_Extent'][key])]
    if max(errors) > step*1.01: raise ValueError('Water geometry differs from independent source bounds')
    groups = handler.get_triangles()
    if len(groups) != 1: raise ValueError('Water material/submesh disagreement')
    material = materials[renderer['m_MaterialList'][0]['m_Path']]; verify(material['sourceBundle'], material['sourceSHA256'])
    colors = dict(material['data']['m_SavedProperties']['m_Colors'])
    color = [colors['_SurfaceOverlay0'][c] for c in 'rgba']
    binary = bytearray(); views = []; accessors = []
    def append(data, target):
        binary.extend(bytes(-len(binary)%4)); i = len(views)
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data), 'target': target})
        binary.extend(data); return i
    def attribute(values, width):
        flat = [v for row in values for v in row]; view = append(struct.pack('<'+'f'*len(flat), *flat), 34962)
        accessors.append({'bufferView': view, 'componentType': 5126, 'count': len(values), 'type': f'VEC{width}',
                          'min': [min(v[a] for v in values) for a in range(width)], 'max': [max(v[a] for v in values) for a in range(width)]})
        return len(accessors)-1
    p, n, uv = attribute(positions, 3), attribute(normals, 3), attribute(uvs, 2)
    indices = [v for a,b,c in groups[0] for v in (a,c,b)]
    if any(i < 0 or i >= len(positions) for i in indices): raise ValueError('Invalid water index')
    view = append(struct.pack('<'+'I'*len(indices), *indices), 34963)
    accessors.append({'bufferView': view, 'componentType': 5125, 'count': len(indices), 'type': 'SCALAR'})
    document = {'asset': {'version': '2.0', 'generator': 'Aniimo Atlas original water geometry QA'}, 'scene': 0,
                'scenes': [{'nodes': [0]}], 'nodes': [{'name': mesh.m_Name, 'mesh': 0}],
                'meshes': [{'primitives': [{'attributes': {'POSITION': p, 'NORMAL': n, 'TEXCOORD_0': uv}, 'indices': 3, 'material': 0}]}],
                'materials': [{'name': material['data']['m_Name']+' / source-overlay static QA', 'doubleSided': True,
                               'pbrMetallicRoughness': {'baseColorFactor': color, 'metallicFactor': 0, 'roughnessFactor': .15}}],
                'buffers': [{'byteLength': len(binary)}], 'bufferViews': views, 'accessors': accessors}
    text = json.dumps(document, separators=(',', ':')).encode(); text += b' '*(-len(text)%4); binary.extend(bytes(-len(binary)%4))
    data = struct.pack('<III', 0x46546c67, 2, 28+len(text)+len(binary))+struct.pack('<II', len(text), 0x4e4f534a)+text+struct.pack('<II', len(binary), 0x004e4942)+binary
    resource_id = next(r['id'] for r in storage['resources'] if r['path'] == platform['prefabPath'])
    filename = f'water-resource-{resource_id}.glb'; (output/filename).write_bytes(data)
    models.append({'resourceIndex': resource_id, 'prefabPath': platform['prefabPath'], 'file': filename, 'sha256': hashlib.sha256(data).hexdigest(),
                   'sourceMesh': {**asset, 'sourceBundle': index['bundle'], 'sourceSHA256': index['sha256']},
                   'sourceMaterial': material, 'sourceBounds': bounds, 'vertices': len(positions), 'triangles': len(indices)//3,
                   'compressed': compressed, 'sourceQuantizationStepMetres': step, 'maxBoundsErrorMetres': max(errors)})
    print('Exported original water', resource_id, len(positions), 'vertices;', len(indices)//3, 'triangles; bounds error', max(errors), flush=True)
placements = [{'packetID': p['packetID'], **i} for p in source_placements['packets'] for i in p['instances'] if i['assetPath'] in {m['prefabPath'] for m in models}]
report = {'schema': 'original-water-models-v1', 'models': models, 'placements': placements,
          'sourcePlacementsSHA256': hashlib.sha256((research/'homeland-xchunk-prefab-placements.json').read_bytes()).hexdigest(),
          'basis': 'Unity(z,y,x), reflected winding, flipped V; native quaternion(-z,-y,-x,w); native scale(z,y,x)',
          'fidelity': 'Original geometry and13 source poses. Static source _SurfaceOverlay0 color swatch, fixed QA roughness0.15. Depth/refraction/absorption/foam/normal animation/SSR/shoreline shader NOT ported.'}
(output/'manifest.json').write_text(json.dumps(report, indent=2)+'\n')
print('Bound original water models to', len(placements), 'unchanged static prefab placements')
