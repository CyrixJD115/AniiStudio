#!/usr/bin/env python3
"""Bounded CPU reference for the straight-line terrain bake DXBC disassembly.

Registers retain uint32 bits; float/integer conversions and destination masks
follow instruction semantics. Texture sampling is supplied explicitly by a
caller, never guessed here. This is offline numerical QA, not a game hook.
"""
import re
import numpy as np

AXES = dict(x=0,y=1,z=2,w=3)
SUPPORTED = {'add','mul','mad','max','min','div','sqrt','frc','round_ni','round_ne','mov','dp2','dp3',
             'utof','itof','ftou','iadd','ineg','and','or','ushr','ishr','umin','ult','ieq','movc','ubfe','bfi',
             'ld_structured_indexable','resinfo_uint_indexable','gather4_indexable','sample_d_indexable','sample_l_indexable','store_uav_typed'}


def split_arguments(text):
    result=[]; depth=0; start=0
    for i,c in enumerate(text):
        if c in '([': depth+=1
        elif c in ')]': depth-=1
        elif c==',' and depth==0: result.append(text[start:i].strip()); start=i+1
    if depth: raise ValueError('Unbalanced shader operand')
    result.append(text[start:].strip()); return result


def parse_program(text):
    result=[]
    for line in text.splitlines():
        line=line.strip()
        if not line or line.startswith('//') or line.startswith('dcl_') or line=='cs_5_0': continue
        if line=='ret': break
        match=re.fullmatch(r'(\w+(?:\([^)]*\))*)\s+(.+)',line)
        if not match: raise ValueError('Unsupported shader statement: '+line)
        operation=match[1].split('(')[0]; saturated=operation.endswith('_sat')
        if saturated: operation=operation[:-4]
        if operation not in SUPPORTED: raise ValueError('Unsupported terrain instruction: '+operation)
        result.append((operation,saturated,split_arguments(match[2])))
    if len(result)>4096: raise ValueError('Reference kernel instruction bound exceeded')
    return result


class Kernel:
    def __init__(self, program, thread_ids, constants=None, buffers=None, textures=None):
        threads=np.asarray(thread_ids,dtype=np.uint32)
        if threads.ndim!=2 or threads.shape[1]!=3 or not 0<len(threads)<=65536: raise ValueError('Invalid bounded thread batch')
        self.program=parse_program(program); self.count=len(threads)
        self.threads=np.column_stack([threads,np.zeros(len(threads),dtype=np.uint32)])
        self.registers=np.zeros((32,len(threads),4),dtype=np.uint32)
        self.constants=np.asarray(constants,dtype=np.uint32) if constants is not None else np.zeros((19,4),dtype=np.uint32)
        self.buffers=buffers or {}; self.textures=textures; self.outputs={}

    @staticmethod
    def swizzle(bits, suffix):
        if not suffix: return bits
        indices=[AXES[c] for c in suffix]
        if len(indices)==1: indices*=4
        if len(indices)!=4: raise ValueError('Expected scalar or complete source swizzle')
        return bits[:,indices]

    def read(self, operand):
        negate=operand.startswith('-'); operand=operand[1:] if negate else operand
        if operand.startswith('l('):
            values=split_arguments(operand[2:-1]); values=values*4 if len(values)==1 else values
            if len(values)!=4: raise ValueError('Invalid literal vector')
            bits=np.array([np.float32(float(v)).view(np.uint32) if any(c in v.lower() for c in '.e') else int(v)&0xffffffff for v in values],dtype=np.uint32)
            bits=np.broadcast_to(bits,(self.count,4))
        else:
            match=re.fullmatch(r'(r\d+|vThreadID|cb0\[[^]]+\])(?:\.([xyzw]+))?',operand)
            if not match: raise ValueError('Unsupported operand: '+operand)
            base,suffix=match[1],match[2]
            if base.startswith('r'):
                index=int(base[1:])
                if index>=32: raise ValueError('Register out of bounds')
                bits=self.registers[index]
            elif base=='vThreadID': bits=self.threads
            else:
                expression=base[4:-1]
                if expression.isdigit(): indices=np.full(self.count,int(expression))
                else:
                    index_match=re.fullmatch(r'(r\d+\.[xyzw])\s*\+\s*(\d+)',expression)
                    if not index_match: raise ValueError('Unsupported constant-buffer index')
                    indices=self.read(index_match[1])[:,0].astype(np.int64)+int(index_match[2])
                if np.any(indices<0) or np.any(indices>=len(self.constants)): raise ValueError('Constant-buffer index out of range')
                bits=self.constants[indices]
            bits=self.swizzle(bits,suffix)
        return bits ^ np.uint32(0x80000000) if negate else bits

    def write(self, destination, bits):
        match=re.fullmatch(r'r(\d+)(?:\.([xyzw]+))?',destination)
        if not match or int(match[1])>=32: raise ValueError('Invalid destination register')
        indices=[AXES[c] for c in match[2] or 'xyzw']
        values=np.asarray(bits,dtype=np.uint32)
        if values.shape!=(self.count,4): values=np.broadcast_to(values,(self.count,4))
        target=self.registers[int(match[1])]
        for i in indices: target[:,i]=values[:,i]

    def run(self):
        for op,saturated,args in self.program:
            dest=args[0]; source=args[1:]
            if op in ('sample_d_indexable','sample_l_indexable','gather4_indexable','resinfo_uint_indexable'):
                if self.textures is None: raise ValueError('Explicit texture bindings required')
                bits=self.textures.instruction(op,source,self)
            elif op=='store_uav_typed':
                self.outputs[dest.split('.')[0]]={'coordinates':self.read(source[0]).copy(),'values':self.read(source[1]).view(np.float32).copy()}
                continue
            elif op=='ld_structured_indexable':
                index=self.read(source[0])[:,0].astype(np.int64); offset=self.read(source[1])[:,0].astype(np.int64)
                resource=re.fullmatch(r't(\d+)\.([xyzw]+)',source[2])
                if not resource: raise ValueError('Invalid structured buffer operand')
                stride,buffer=self.buffers[int(resource[1])]; buffer=np.asarray(buffer,dtype=np.uint32).reshape(-1)
                start=(index*stride+offset)//4
                if np.any(offset%4): raise ValueError('Unaligned structured load')
                suffix=resource[2]; components=[AXES[c] for c in suffix]
                if len(components)==1: components*=4
                if len(components)!=4: raise ValueError('Unsupported structured swizzle')
                addresses=start[:,None]+np.array(components)
                # Only components actually written must be valid; scalar loads
                # broadcast their single requested word, including offset8 loads.
                if np.any(addresses<0) or np.any(addresses>=len(buffer)): raise ValueError('Structured load out of bounds')
                bits=buffer[addresses]
            else:
                raw=[self.read(s) for s in source]; floats=[v.view(np.float32) for v in raw]
                if op=='mov': bits=raw[0].copy()
                elif op=='movc': bits=np.where(raw[0]!=0,raw[1],raw[2])
                elif op in ('add','mul','mad','max','min','div','sqrt','frc','round_ni','round_ne','dp2','dp3'):
                    a=floats[0]
                    with np.errstate(divide='ignore',invalid='ignore',over='ignore'):
                        if op=='add': value=a+floats[1]
                        elif op=='mul': value=a*floats[1]
                        elif op=='mad': value=a*floats[1]+floats[2]
                        elif op=='max': value=np.maximum(a,floats[1])
                        elif op=='min': value=np.minimum(a,floats[1])
                        elif op=='div': value=a/floats[1]
                        elif op=='sqrt': value=np.sqrt(a)
                        elif op=='frc': value=a-np.floor(a)
                        elif op=='round_ni': value=np.floor(a)
                        elif op=='round_ne': value=np.rint(a)
                        else:
                            width=int(op[-1]); value=np.repeat(np.sum(a[:,:width]*floats[1][:,:width],axis=1)[:,None],4,axis=1)
                    bits=np.asarray(value,dtype=np.float32).view(np.uint32)
                elif op=='utof': bits=raw[0].astype(np.float32).view(np.uint32)
                elif op=='itof': bits=raw[0].view(np.int32).astype(np.float32).view(np.uint32)
                elif op=='ftou':
                    if np.any(~np.isfinite(floats[0])) or np.any(floats[0]<0) or np.any(floats[0]>=4294967296):
                        raise ValueError('Undefined float-to-uint input in reference batch')
                    bits=np.trunc(floats[0]).astype(np.uint32)
                elif op=='iadd': bits=raw[0]+raw[1]
                elif op=='ineg': bits=np.uint32(0)-raw[0]
                elif op=='and': bits=raw[0]&raw[1]
                elif op=='or': bits=raw[0]|raw[1]
                elif op=='ushr': bits=raw[0]>>(raw[1]&31)
                elif op=='ishr': bits=(raw[0].view(np.int32)>>(raw[1]&31)).astype(np.uint32)
                elif op=='umin': bits=np.minimum(raw[0],raw[1])
                elif op=='ult': bits=np.where(raw[0]<raw[1],np.uint32(0xffffffff),np.uint32(0))
                elif op=='ieq': bits=np.where(raw[0]==raw[1],np.uint32(0xffffffff),np.uint32(0))
                elif op=='ubfe':
                    width,offset,value=raw; mask=((np.uint64(1)<<(width&31))-1).astype(np.uint32); bits=(value>>(offset&31))&mask
                elif op=='bfi':
                    width,offset,insert,base=raw; mask=((np.uint64(1)<<(width&31))-1).astype(np.uint32)<<(offset&31)
                    bits=(base&~mask)|((insert<<(offset&31))&mask)
                else: raise ValueError('Unhandled instruction: '+op)
            if saturated: bits=np.clip(bits.view(np.float32),0,1).astype(np.float32).view(np.uint32)
            self.write(dest,bits)
        return self.outputs
