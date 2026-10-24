#!/usr/bin/env python3
"""Native PBR derivatives from original shipped terrain atlases, not painted maps.

Original final VT shader squares diffuse RGB and reconstructs normal Z from XY.
Packed source alpha/height retained separately, never used as ground opacity.
"""
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from UnityPy.enums import BuildTarget, TextureFormat
from UnityPy.export.Texture2DConverter import parse_image_data


def native_maps(diffuse, normal):
    d=np.asarray(diffuse,dtype=np.float32)/255;n=np.asarray(normal,dtype=np.float32)/255
    linear=d[:,:,:3]**2
    color=np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
    xy=n[:,:,:2]*2-1;z=np.sqrt(np.maximum(1-np.sum(xy*xy,axis=2),0))
    encoded=np.concatenate([xy,z[:,:,None]],axis=2)*.5+.5
    # Native terrain UV increases with source worldZ. Flip image rows, not
    # tangent normal Y, to match SceneKit's image origin convention.
    color=np.rint(np.clip(color,0,1)*255).astype(np.uint8)[::-1].copy()
    encoded=np.rint(np.clip(encoded,0,1)*255).astype(np.uint8)[::-1].copy()
    roughness=np.asarray(normal,dtype=np.uint8)[:,:,3][::-1].copy()
    return color,encoded,roughness


if __name__=='__main__':
    research,output=map(Path,sys.argv[1:3]);output.mkdir(parents=True,exist_ok=True)
    records_path=research/'homeland-terrain-sector-records.json';records=json.loads(records_path.read_text())['records']
    shader_dir=research/'terrain-vt-shader-verified';proof=json.loads((shader_dir/'manifest.json').read_text())
    program=next(p for p in proof['programs'] if p['file']=='program-p4-s0-v22.dxbc')
    if hashlib.sha256((shader_dir/program['file']).read_bytes()).hexdigest()!=program['sha256']:raise ValueError('Original VT decode program changed')
    assembly=(shader_dir/'program-p4-s0-v22.asm').read_text()
    for snippet in ['mul r7.xyz, r5.xyzx, r5.xyzx','mad r8.xy, r6.xyxx','sqrt r8.z, r0.w']:
        if snippet not in assembly:raise ValueError('VT source decode needs re-audit')
    tiles=[]
    for record in records:
        if record['level']!=0:continue
        data=(research/record['recordFile']).read_bytes()
        if hashlib.sha256(data).hexdigest()!=record['decodedSHA256']:raise ValueError('Original sector changed')
        images=[];source=[]
        for role in ['atlasDiffuse','atlasNormal']:
            meta=record['maps'][role];payload=data[meta['offset']:meta['offset']+meta['bytes']]
            if hashlib.sha256(payload).hexdigest()!=meta['sha256']:raise ValueError('Original atlas changed')
            image=parse_image_data(payload,136,136,TextureFormat.BC7,(2022,3,0,0),BuildTarget.StandaloneWindows64,flip=False).convert('RGBA')
            images.append(image);source.append(meta['sha256'])
        x,z=record['x'],record['z'];color,normal,roughness=native_maps(*images)
        files={}
        for role,pixels in [('color',color),('normal',normal),('roughness',roughness)]:
            filename=f'sector-{x}-{z}-{role}.png';Image.fromarray(pixels).save(output/filename)
            files[role]={'file':filename,'sha256':hashlib.sha256((output/filename).read_bytes()).hexdigest()}
        tiles.append({'x':x,'z':z,'sourceAtlasHashes':source,**files})
    report={'schema':'original-terrain-native-materials-v1','tiles':tiles,'sourceRecordsSHA256':hashlib.sha256(records_path.read_bytes()).hexdigest(),
            'sourceDecodeProgramSHA256':program['sha256'],'logicalPixels':128,'gutterPixels':4,'imagePixels':136,
            'scope':'Original shipped low-resolution atlases decoded for native PBR. Albedo opaque RGB, XY normal reconstruction, packed W roughness adaptation; source B height and diffuse A not opacity. Higher virtual-texture resolution/lighting/weather/decal behavior not reproduced.'}
    (output/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Exported native material derivatives for',len(tiles),'original64m sectors; original source geometry untouched')
