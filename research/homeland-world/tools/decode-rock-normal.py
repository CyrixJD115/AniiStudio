#!/usr/bin/env python3
"""EV_TintRock primary normal decoding from verified TOPPING PS instructions.

program-p4-s0-v77.asm: sample normal as (R,G,A); X=R*A, unpack XY,
Z=sqrt(1-saturate(dot(XY,XY))); apply BaseLayer_NormalScale to XY.
Only this base layer is decoded here; topping/detail blending is separate.
"""
import math


def decode_pixel(red,green,alpha,scale=1):
    if any(not math.isfinite(v) for v in (red,green,alpha,scale)) or any(not 0<=v<=1 for v in (red,green,alpha)):
        raise ValueError("Invalid source normal sample")
    x,y=red*alpha*2-1,green*2-1
    z=max(math.sqrt(max(0,1-min(x*x+y*y,1))),1e-16)
    x*=scale;y*=scale
    length=math.sqrt(x*x+y*y+z*z)
    return x/length,y/length,z/length


def decode_image(image,scale=1):
    import numpy as np
    from PIL import Image
    if not math.isfinite(scale):raise ValueError("Nonfinite normal scale")
    rgba=np.asarray(image.convert("RGBA"),dtype=np.float32)/255
    x=rgba[:,:,0]*rgba[:,:,3]*2-1;y=rgba[:,:,1]*2-1
    z=np.maximum(np.sqrt(np.maximum(0,1-np.minimum(x*x+y*y,1))),1e-16)
    x*=scale;y*=scale
    length=np.sqrt(x*x+y*y+z*z)
    # glTF V was flipped during geometry export, so negate the tangent Y here.
    normal=np.stack((x/length,-y/length,z/length),axis=2)
    encoded=np.rint(np.clip(normal*.5+.5,0,1)*255).astype(np.uint8)
    return Image.fromarray(encoded)
