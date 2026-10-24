#!/usr/bin/env python3
"""Explicit texture-array bindings for offline terrain-kernel numerical QA.

Gather order follows Microsoft's SM5 instruction documentation:
https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/gather4--sm5---asm-
Caller supplies
float32 channel data, mips and sampler addressing; no implicit color conversion.
"""
import re
import numpy as np


class Textures:
    def __init__(self, levels, samplers):
        self.levels=levels;self.samplers=samplers
        for chain in levels.values():
            if not chain:raise ValueError('Empty mip chain')
            for mip in chain:
                if mip.ndim!=4 or mip.shape[-1]!=4 or mip.dtype!=np.float32 or not np.all(np.isfinite(mip)):
                    raise ValueError('Expected finite float32 array/layer/height/width/RGBA data')

    @staticmethod
    def address(indices,size,mode):
        if mode=='clamp':return np.clip(indices,0,size-1)
        if mode=='repeat':return indices%size
        raise ValueError('Unknown explicit sampler addressing')

    def point(self,mip,x,y,layer,mode):
        return mip[np.clip(layer,0,mip.shape[0]-1),self.address(y,mip.shape[1],mode),self.address(x,mip.shape[2],mode)]

    def sample(self,resource,uv,lod,mode):
        chain=self.levels[resource];lod=np.clip(lod,0,len(chain)-1)
        lo=np.floor(lod).astype(int);hi=np.minimum(lo+1,len(chain)-1);fraction=(lod-lo)[:,None]
        samples=[]
        for requested in (lo,hi):
            output=np.zeros((len(uv),4),dtype=np.float32)
            for level in np.unique(requested):
                mask=requested==level;mip=chain[level];p=uv[mask]
                x=p[:,0]*mip.shape[2]-.5;y=p[:,1]*mip.shape[1]-.5
                ix=np.floor(x).astype(int);iy=np.floor(y).astype(int);layer=np.floor(p[:,2]+.5).astype(int)
                fx=(x-ix)[:,None];fy=(y-iy)[:,None]
                top=self.point(mip,ix,iy,layer,mode)*(1-fx)+self.point(mip,ix+1,iy,layer,mode)*fx
                bottom=self.point(mip,ix,iy+1,layer,mode)*(1-fx)+self.point(mip,ix+1,iy+1,layer,mode)*fx
                output[mask]=top*(1-fy)+bottom*fy
            samples.append(output)
        return np.asarray(samples[0]*(1-fraction)+samples[1]*fraction,dtype=np.float32)

    def instruction(self,operation,operands,kernel):
        if operation=='resinfo_uint_indexable':
            resource=re.fullmatch(r't(\d+)\.([xyzw]+)',operands[1])
            if not resource:raise ValueError('Invalid resource info operand')
            chain=self.levels[int(resource[1])];level=int(kernel.read(operands[0])[0,0]);mip=chain[level]
            data=np.broadcast_to(np.array([mip.shape[2],mip.shape[1],mip.shape[0],len(chain)],dtype=np.uint32),(kernel.count,4))
            return kernel.swizzle(data,resource[2])
        resource=re.fullmatch(r't(\d+)\.([xyzw]+)',operands[1]);sampler=re.fullmatch(r's(\d+)(?:\.([xyzw]))?',operands[2])
        if not resource or not sampler:raise ValueError('Invalid texture instruction operand')
        index=int(resource[1]);mode=self.samplers[int(sampler[1])];uv=kernel.read(operands[0]).view(np.float32)
        if not np.all(np.isfinite(uv)):raise ValueError('Nonfinite texture coordinates')
        if operation=='gather4_indexable':
            mip=self.levels[index][0];x=np.floor(uv[:,0]*mip.shape[2]-.5).astype(int);y=np.floor(uv[:,1]*mip.shape[1]-.5).astype(int)
            layer=np.floor(uv[:,2]+.5).astype(int);component='xyzw'.index(sampler[2] or 'x')
            # SM5: lower-left, lower-right, upper-right, upper-left.
            values=np.stack([self.point(mip,x+dx,y+dy,layer,mode)[:,component] for dx,dy in [(0,1),(1,1),(1,0),(0,0)]],axis=1)
        else:
            if operation=='sample_l_indexable':lod=kernel.read(operands[3]).view(np.float32)[:,0]
            elif operation=='sample_d_indexable':
                mip=self.levels[index][0];scale=np.array([mip.shape[2],mip.shape[1]],dtype=np.float32)
                dx=kernel.read(operands[3]).view(np.float32)[:,:2]*scale;dy=kernel.read(operands[4]).view(np.float32)[:,:2]*scale
                rho=np.maximum(np.sum(dx*dx,axis=1),np.sum(dy*dy,axis=1))
                lod=np.log2(np.maximum(rho,np.finfo(np.float32).tiny))*.5
            else:raise ValueError('Unsupported texture operation')
            values=self.sample(index,uv,lod,mode)
        return kernel.swizzle(np.asarray(values,dtype=np.float32).view(np.uint32),resource[2])
