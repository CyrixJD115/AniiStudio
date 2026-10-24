#!/usr/bin/env python3
"""Compare source plant origins with original height terrain; never snap placements.

Positive residuals may need separate rock/cliff/other surface geometry. This
diagnostic cannot establish that an original placement is wrong.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

world, transforms_path, output = map(Path, sys.argv[1:4])
sources = json.loads((world / "sources.json").read_text())
tiles = {}
for tile in sources["terrain"]:
    data = (world / tile["file"]).read_bytes()
    if hashlib.sha256(data).hexdigest() != tile["fileSHA256"]:
        raise ValueError("Terrain source changed")
    tiles[(tile["x"],tile["z"])] = struct.unpack("<"+"H"*(257*257),data)


def height(x,z):
    if not -512 <= x < 512 or not -512 <= z < 512:
        return None
    gx,gz=(x+512)*2,(z+512)*2
    tx,tz=min(7,int(gx)//256),min(7,int(gz)//256)
    lx,lz=gx-tx*256,gz-tz*256
    ix,iz=int(lx),int(lz)
    fx,fz=lx-ix,lz-iz
    data=tiles[(tx,tz)]
    a=data[iz*257+ix];b=data[iz*257+min(ix+1,256)]
    c=data[min(iz+1,256)*257+ix];d=data[min(iz+1,256)*257+min(ix+1,256)]
    return ((a*(1-fx)+b*fx)*(1-fz)+(c*(1-fx)+d*fx)*fz)*600/32766


report=[]
source=json.loads(transforms_path.read_text())
for ids,label in [([1,17],"original authored grass"),([7],"current pine prototype7")]:
    residuals=[];outside=0;samples=[]
    for chunk in source["chunks"]:
        if chunk["prototypeID"] not in ids:continue
        for instance in chunk["instances"]:
            x,y,z=instance["position"]
            terrain=height(x,z)
            if terrain is None:outside+=1;continue
            delta=y-terrain;residuals.append(delta)
            samples.append({"chunk":chunk["chunk"],"prototypeID":chunk["prototypeID"],
                            "sourceIndex":instance["sourceIndex"],"position":[x,y,z],"heightResidualMetres":delta})
    residuals.sort()
    report.append({"label":label,"sampledOrigins":len(residuals),"outsideHeightTerrain":outside,
                   "medianResidualMetres":residuals[len(residuals)//2],"minResidualMetres":min(residuals),
                   "maxResidualMetres":max(residuals),"within25cm":sum(abs(d)<=.25 for d in residuals),
                   "aboveHeightTerrainOver1m":sum(d>1 for d in residuals),
                   "largestPositiveResiduals":sorted(samples,key=lambda x:-x["heightResidualMetres"])[:10]})
output.write_text(json.dumps({"interpretation":"Height-terrain-only diagnostic; do not move original instances. Other surface geometry/hole semantics not included.","groups":report},indent=2)+"\n")
for row in report:print({k:v for k,v in row.items() if k!="largestPositiveResiduals"})
