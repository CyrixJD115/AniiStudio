#!/usr/bin/env python3
"""Overlay bounded original-kernel HQ pages on the checksum-bound source atlas set."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from PIL import Image

spec=importlib.util.spec_from_file_location('native_material_decode',Path(__file__).with_name('export-native-terrain-materials.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

if __name__=='__main__':
    research,output=map(Path,sys.argv[1:3]);output.mkdir(parents=True,exist_ok=True)
    baseline=research/'native-terrain-materials';manifest=json.loads((baseline/'manifest.json').read_text())
    tiles={(t['x'],t['z']):t for t in manifest['tiles']}
    for tile in tiles.values():
        for role in ['color','normal','roughness']:
            entry=tile[role];data=(baseline/entry['file']).read_bytes()
            if hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('Original native material changed')
            (output/entry['file']).write_bytes(data)
    for x,z in [(7,5),(8,5),(7,6),(8,6)]:
        folder=research/f'terrain-hq-1024-{x}-{z}';proof=json.loads((folder/'manifest.json').read_text())
        if proof['sector']!=[x,z] or proof['logicalPixels']!=1024 or proof['gutterPixels']!=4 or proof['resolution']!=1032:
            raise ValueError('HQ terrain page identity/dimensions mismatch')
        if proof['batchPixelLimit']>65536:raise ValueError('Unbounded reference batch')
        diffuse=Image.open(folder/'diffuse.png').convert('RGBA');normal=Image.open(folder/'packed-normal.png').convert('RGBA')
        if diffuse.size!=(1032,1032) or normal.size!=diffuse.size:raise ValueError('HQ image dimensions differ from proof')
        native=module.native_maps(diffuse,normal);tile=tiles[x,z]
        for role,pixels in zip(['color','normal','roughness'],native):
            filename=f'sector-{x}-{z}-{role}.png';Image.fromarray(pixels).save(output/filename)
            tile[role]={'file':filename,'sha256':hashlib.sha256((output/filename).read_bytes()).hexdigest()}
        tile.update(logicalPixels=1024,gutterPixels=4,imagePixels=1032,
                    referenceProgramSHA256=proof['shaderSHA256'],referenceSectorSHA256=proof['sourceSectorSHA256'],
                    sourceReferenceManifestSHA256=hashlib.sha256((folder/'manifest.json').read_bytes()).hexdigest())
    manifest['scope']='Original shipped low-resolution materials plus4 original-kernel CPU reference HQ pages around captured residential anchors. Empirically validated shader setup; not live-engine pixel-exact material/lighting reproduction.'
    manifest['highResolutionSectors']=[[7,5],[8,5],[7,6],[8,6]]
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Prepared256native terrain sectors;4nearby sectors have1024logical pixels and4pixel gutters')
