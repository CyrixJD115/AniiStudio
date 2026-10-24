#!/usr/bin/env python3
"""Compare original-kernel CPU output against independent shipped BC7 atlases."""
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from UnityPy.enums import BuildTarget, TextureFormat
from UnityPy.export.Texture2DConverter import parse_image_data

research,output=map(Path,sys.argv[1:3]);output.mkdir(parents=True,exist_ok=True)
records=json.loads((research/'homeland-terrain-sector-records.json').read_text())['records'];rows=[];images={}
for x,z,folder in [(8,5,'terrain-reference-home-atlas'),(9,5,'terrain-reference-atlas-9-5'),(8,6,'terrain-reference-atlas-8-6')]:
    root=research/folder;settings=json.loads((root/'manifest.json').read_text())
    record=next(r for r in records if (r['level'],r['x'],r['z'])==(0,x,z));data=(research/record['recordFile']).read_bytes()
    if hashlib.sha256(data).hexdigest()!=settings['sourceSectorSHA256']:raise ValueError('Independent source-sector mismatch')
    comparisons={}
    for role,file in [('atlasDiffuse','diffuse'),('atlasNormal','packed-normal')]:
        meta=record['maps'][role];payload=data[meta['offset']:meta['offset']+meta['bytes']]
        if hashlib.sha256(payload).hexdigest()!=meta['sha256']:raise ValueError('Original shipped atlas changed')
        golden=parse_image_data(payload,136,136,TextureFormat.BC7,(2022,3,0,0),BuildTarget.StandaloneWindows64,flip=False).convert('RGBA')
        golden.save(output/f'original-{x}-{z}-{file}.png')
        actual=Image.open(root/f'{file}.png').convert('RGBA')
        a=np.asarray(actual).astype(float);b=np.asarray(golden).astype(float)
        difference=abs(a-b);inside=difference[4:-4,4:-4]
        comparisons[file]={'channelMAE':difference.mean(axis=(0,1)).tolist(),'interiorChannelMAE':inside.mean(axis=(0,1)).tolist(),
                           'maximumChannelError':difference.max(axis=(0,1)).tolist(), 'p95ChannelError':np.quantile(difference,.95,axis=(0,1)).tolist(),
                           'originalMapSHA256':meta['sha256'],'outputImageSHA256':hashlib.sha256((root/f'{file}.png').read_bytes()).hexdigest()}
        images[(x,z,file,'reference')]=a;images[(x,z,file,'original')]=b
        if file=='diffuse':
            comparison=np.concatenate([a,b,np.clip(difference*4,0,255)],axis=1).astype(np.uint8)
            Image.fromarray(comparison).convert('RGB').resize((1020,340)).save(output/f'comparison-{x}-{z}.jpg',quality=60)
    rows.append({'x':x,'z':z,'uniforms':settings['uniforms'],'quadUV':settings['quadUV'],'comparisons':comparisons})
    print('Sector',x,z,'diffuse MAE',comparisons['diffuse']['channelMAE'],'packed-normal MAE',comparisons['packed-normal']['channelMAE'])
seams=[]
for kind in ['diffuse','packed-normal']:
    for direction,neighbor in [('x',(9,5)),('z',(8,6))]:
        result={}
        for source in ['reference','original']:
            a=images[(8,5,kind,source)];b=images[(*neighbor,kind,source)]
            overlap=(a[:,-8:]-b[:,:8]) if direction=='x' else (a[-8:]-b[:8])
            result[source+'ChannelMAE']=np.mean(abs(overlap),axis=(0,1)).tolist()
        seams.append({'direction':direction,'map':kind,**result})
(output/'manifest.json').write_text(json.dumps({'scope':'Independent shipped-atlas comparison; source BC7 loss and float/filter differences remain. No live engine CB capture or pixel-exact claim.',
                                              'sectors':rows,'eightPixelOverlapSeams':seams},indent=2)+'\n')
