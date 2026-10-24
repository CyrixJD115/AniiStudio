#!/usr/bin/env python3
"""Bind validated original pine variants to their exact streamed prototype IDs."""
import hashlib
import json
from pathlib import Path
import sys

research, output = map(Path, sys.argv[1:3])
definitions = {p['id']: p for p in json.loads((research/'homeland-vegetation-stream-definitions.json').read_text())['prototypes']}
chunks = json.loads((research/'homeland-vegetation-transforms.json').read_text())['chunks']
models = []
for prototype, filename in [(5, 'original-home-pine-c-lod0.glb'), (27, 'original-home-pine-h-lod0.glb')]:
    path = output.parent / filename
    proof = json.loads(path.with_suffix('.provenance.json').read_text())
    definition = definitions[prototype]
    if proof['prototypeID'] != prototype or proof['prefab'] != definition['name'] or proof['explicitCurrentMesh'] != definition['meshLODs'][0][0]:
        raise ValueError('Variant source identity mismatch')
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != proof['outputSHA256'] or proof['maxGeometryBoundsErrorMetres'] > proof['sourcePositionQuantizationStepMetres']:
        raise ValueError('Variant geometry/checksum mismatch')
    models.append({'prototypeID': prototype, 'prefab': definition['name'], 'file': filename, 'sha256': digest,
                   'sourcePlacements': sum(len(c['instances']) for c in chunks if c['prototypeID'] == prototype)})
output.write_text(json.dumps({'schema': 'original-pine-variants-v1', 'models': models}, indent=2)+'\n')
print('Bound', len(models), 'original pine variants to', sum(m['sourcePlacements'] for m in models), 'unchanged source placements')
