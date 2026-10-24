#!/usr/bin/env python3
"""Run original terrain bake instructions on an offline patch of real source maps.

Shader logic and source data are preserved. UV/border uniforms are explicitly
dimension-derived QA settings, NOT captured live engine constant buffers.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from UnityPy.enums import BuildTarget, TextureFormat
from UnityPy.export.Texture2DConverter import parse_image_data


def load(name,file):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


core=load('terrain_reference_kernel','dxbc-reference-kernel.py');sampling=load('terrain_reference_sampling','dxbc-reference-textures.py')


if __name__=='__main__':
    research,output=map(Path,sys.argv[1:3]);output.mkdir(parents=True,exist_ok=True)
    atlas_mode='--atlas' in sys.argv[3:];sector=(8,5);logical=128
    for option in sys.argv[3:]:
        if option=='--atlas':continue
        if option.startswith('--sector='):
            sector=tuple(map(int,option.split('=',1)[1].split(',')))
            if len(sector)!=2 or not all(0<=v<16 for v in sector):raise ValueError('Invalid source sector')
        elif option.startswith('--logical='):
            logical=int(option.split('=',1)[1])
            if logical not in (128,256,512,1024,2048):raise ValueError('Unsupported bounded physical-page size')
        else:raise ValueError('Expected --atlas, --sector=x,z and/or --logical=resolution')
    root=json.loads((research/'homeland-runtime-terrain-root.json').read_text())
    records=json.loads((research/'homeland-terrain-sector-records.json').read_text())['records']
    record=next(r for r in records if (r['level'],r['x'],r['z'])==(0,*sector))
    data=(research/record['recordFile']).read_bytes()
    if hashlib.sha256(data).hexdigest()!=record['decodedSHA256']:raise ValueError('Original sector changed')
    maps={}
    for slot,role,channels in [(0,'index',4),(1,'weight',1),(2,'tint',4),(3,'wetness',1)]:
        meta=record['maps'][role];raw=data[meta['offset']:meta['offset']+meta['bytes']]
        array=np.frombuffer(raw,dtype=np.uint8).reshape(meta['height'],meta['width'],channels).astype(np.float32)/255
        if channels==1:
            rgba=np.zeros((meta['height'],meta['width'],4),dtype=np.float32);rgba[:,:,0]=array[:,:,0];rgba[:,:,3]=1;array=rgba
        maps[slot]=[array[None]]
    layer_ids=sorted(set(np.rint(maps[0][0][0,:,:,[0,2]].reshape(-1)*255).astype(int).tolist()))
    if any(i>=root['layerCount'] for i in layer_ids):raise ValueError('Unmapped source material')
    texture_manifest=json.loads((research/'terrain-layer-textures/manifest.json').read_text())
    for slot,kind in [(4,'Diffuse'),(5,'Normal')]:
        layer_mips=[]
        for identity in layer_ids:
            entry=next(t for t in texture_manifest['textures'] if t['kind']==kind and t['layerIndex']==identity)
            packed=(research/'terrain-layer-textures'/entry['mipFile']).read_bytes()
            if hashlib.sha256(packed).hexdigest()!=entry['mipSHA256']:raise ValueError('Preserved source mip chain changed')
            chain=[]
            for mip in entry['mips']:
                chunk=packed[mip['offset']:mip['offset']+mip['bytes']]
                image=parse_image_data(chunk,mip['width'],mip['height'],TextureFormat.BC7,(2022,3,0,0),BuildTarget.StandaloneWindows64,flip=False)
                values=np.asarray(image.convert('RGBA'),dtype=np.float32)/255
                if kind=='Diffuse':
                    rgb=values[:,:,:3];values[:,:,:3]=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
                chain.append(values)
            layer_mips.append(chain)
        maps[slot]=[np.stack([chain[level] for chain in layer_mips]) for level in range(len(layer_mips[0]))]
    sector_start=np.array([-512+sector[0]*64,-512+sector[1]*64])
    if atlas_mode:
        size=logical+8;world_extent=64*size/logical;center=sector_start+32;step=1/logical;uv_origin=np.array([-4/logical,-4/logical])
    else:
        size=64;world_extent=2.0;center=np.array([32,-135.5]) if sector==(8,5) else sector_start+32;step=world_extent/64/size;uv_origin=(center-sector_start-world_extent/2)/64
    uniforms=np.zeros((19,4),dtype=np.float32)
    uniforms[0]=[128/136,128/136,4/136,4/136];uniforms[1]=uniforms[0]
    uniforms[2]=[1024,root['layerCount']/255,0,0]
    remap=np.full(256,255,dtype=np.uint8)
    for resident,identity in enumerate(layer_ids):remap[identity]=resident
    words=uniforms.view(np.uint32);words[3:]=remap.view(np.uint32).reshape(16,4)
    buffers={6:(4,np.zeros(1,dtype=np.uint32))}
    for slot,row in [(7,[*uv_origin,step,0]),(8,[1/129,1/129,128/129,0]),(9,[(sector_start[0]+512)/1024,(sector_start[1]+512)/1024,64/1024,0])]:
        buffers[slot]=(16,np.array([row],dtype=np.float32).view(np.uint32))
    for slot,key,stride in [(10,'tilingParams',4),(11,'averageColor',16),(12,'wetAlbedo',16),(13,'wetRoughness',4)]:
        buffers[slot]=(stride,np.asarray(root[key],dtype=np.float32).view(np.uint32))
    shader_dir=research/'terrain-bake-shader-inspection';proof=json.loads((shader_dir/'manifest.json').read_text())['shaders'][0]['kernels'][0]
    code=(shader_dir/proof['file']).read_bytes()
    if hashlib.sha256(code).hexdigest()!=proof['sha256']:raise ValueError('Original source kernel changed')
    assembly=(shader_dir/Path(proof['file']).with_suffix('.asm').name).read_text()
    bindings=sampling.Textures(maps,{0:'clamp',1:'repeat'})
    pixels={slot:np.empty((size*size,4),dtype=np.uint8) for slot in ['u6','u7']}
    minima={slot:np.full(4,np.inf) for slot in pixels};maxima={slot:np.full(4,-np.inf) for slot in pixels};batches=0
    for start in range(0,size*size,8192):
        end=min(start+8192,size*size);indices=np.arange(start,end,dtype=np.uint32)
        threads=np.column_stack([indices%size,indices//size,np.zeros(len(indices),dtype=np.uint32)])
        outputs=core.Kernel(assembly,threads,words,buffers,bindings).run()
        for slot in pixels:
            values=outputs[slot]['values']
            if not np.all(np.isfinite(values)):raise ValueError('Nonfinite original shader output')
            pixels[slot][start:end]=np.rint(np.clip(values,0,1)*255).astype(np.uint8)
            minima[slot]=np.minimum(minima[slot],values.min(axis=0));maxima[slot]=np.maximum(maxima[slot],values.max(axis=0))
        batches+=1
        if batches%16==0:print('Completed',end,'of',size*size,'source-shader pixels',flush=True)
    statistics={}
    for name,slot in [('diffuse','u7'),('packed-normal','u6')]:
        Image.fromarray(pixels[slot].reshape(size,size,4)).save(output/f'{name}.png')
        statistics[name]={'minimum':minima[slot].tolist(),'maximum':maxima[slot].tolist()}
    Image.open(output/'diffuse.png').convert('RGB').resize((512,512),Image.Resampling.NEAREST).save(output/'diffuse-preview.jpg',quality=60)
    report={'scope':'CPU reference of full original straight-line kernel on actual source maps; dimension-derived UV uniforms and sampler modes NOT live-verified. Float32 MAD/filter differences may differ from GPU.',
            'shaderSHA256':proof['sha256'],'sourceSectorSHA256':record['decodedSHA256'],'sector':list(sector),'layerIDs':layer_ids,'centerWorldXZ':center.tolist(),
            'worldExtentMetres':world_extent,'resolution':size,'logicalPixels':logical if atlas_mode else None,'gutterPixels':4 if atlas_mode else None,
            'batchCount':batches,'batchPixelLimit':8192,'atlasComparisonMode':atlas_mode,'uniforms':uniforms[:3].tolist(),'sectorUVOrigin':uv_origin.tolist(),
            'sectorUVStep':step,'quadUV':[1/129,1/129,128/129,0],'samplers':{'0':'linear clamp','1':'trilinear repeat'},'statistics':statistics}
    (output/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Evaluated complete original terrain shader over',size*size,'real home-patch pixels; materials',layer_ids)
