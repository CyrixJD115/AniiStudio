#!/usr/bin/env python3
"""Original patched PineB geometry with an explicitly static palette/PBR adaptation.

Uses the PineA prefab's current explicit mesh/material references. Does not replace
it with an old mesh to fit stale chunk bounds. Live global tint/wind/SSS unported.
"""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
import numpy as np
from PIL import Image
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

if len(sys.argv) not in (4, 5):
    raise ValueError("Expected BUNDLE_ROOT RESEARCH OUTPUT_GLB [PROTOTYPE_ID]")
root, research, output = map(Path, sys.argv[1:4])
prototype_id = int(sys.argv[4]) if len(sys.argv) == 5 else 7
spec = importlib.util.spec_from_file_location("vertex_codec", Path(__file__).with_name("decode-environment-vertices.py"))
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)
metadata = json.loads((research / "homeland-vegetation-mesh-metadata.json").read_text())["meshes"]
definitions = json.loads((research / "homeland-vegetation-stream-definitions.json").read_text())["prototypes"]
definition = next(p for p in definitions if p["id"] == prototype_id)
reference = next(p for p in definitions if p["id"] == 7)
if prototype_id not in (5, 7, 27) or definition["materialLODs"][0] != reference["materialLODs"][0] or len(definition["meshLODs"][0]) != 1:
    raise ValueError("Only explicit pine variants sharing the verified original material slots are supported")
record = metadata[definition["meshLODs"][0][0]]
source = root / record["sourceBundle"]
if hashlib.sha256(source.read_bytes()).hexdigest() != record["sourceSHA256"]:
    raise ValueError("Original mesh source changed")
environment = UnityPy.load(str(source))
mesh = next(o for o in environment.objects if o.path_id == record["pathID"] and o.assets_file.name.lower() == record["cab"].lower()).read()
handler = MeshHandler(mesh); handler.process()
positions, normals, uvs, unity_positions = [], [], [], []
for p, n, uv in zip(handler.m_Vertices, handler.m_Normals, handler.m_UV0):
    xyz, normal, texcoord = codec.decode(p, n, uv)
    unity_positions.append(xyz)
    positions.append([xyz[2], xyz[1], xyz[0]])
    normals.append([normal[2], normal[1], normal[0]])
    uvs.append([texcoord[0], 1-texcoord[1]])
errors = []
for axis, key in enumerate("xyz"):
    low, high = min(p[axis] for p in unity_positions), max(p[axis] for p in unity_positions)
    errors += [abs((low+high)/2-getattr(mesh.m_LocalAABB.m_Center,key)),
               abs((high-low)/2-getattr(mesh.m_LocalAABB.m_Extent,key))]
quantization_step = max(2*(1 << (3+((p[3] >> 1)&7)))/65535 for p in handler.m_Vertices)
if max(errors) > quantization_step or len(positions) != record["vertexCount"] or not 0 < len(positions) < 65536:
    raise ValueError(f"Decoded current pine differs from bounds: vertices={len(positions)}, errors={errors}")
groups = handler.get_triangles()
if len(groups) != 2:
    raise ValueError("Expected explicit leaf/trunk material groups")


def linear(rgb):
    return np.where(rgb <= .04045, rgb/12.92, ((rgb+.055)/1.055)**2.4)


def srgb(rgb):
    rgb = np.clip(rgb,0,1)
    return np.where(rgb <= .0031308, rgb*12.92, 1.055*rgb**(1/2.4)-.055)


def checked_image(label, role):
    folder = research / "pine-textures" / label
    manifest = json.loads((folder / "manifest.json").read_text())
    entry = next(t for t in manifest["textures"] if t["role"] == role)
    path = folder / entry["file"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != entry["imageSHA256"]:
        raise ValueError("Preserved source texture changed")
    return Image.open(path)


base = np.asarray(checked_image("leaf", "_BaseMap").convert("RGBA"), dtype=np.float32)/255
palette = np.asarray(checked_image("leaf", "_TintPalette").convert("RGB"), dtype=np.float32)/255
local_palette = np.asarray(checked_image("leaf", "_LocalTintPalette").convert("RGB"), dtype=np.float32)/255
# Deliberately static QA settings: palette coordinate0, height/AO blend0.5.
# The original shader's color equation is retained, not direct use of the blue mask.
tint = (linear(palette[0,0]) + linear(local_palette[0,0]))*.5
rgb = linear(base[:,:,:3])*(1+base[:,:,3:4]*(2*tint-1))
rgba = np.empty(base.shape, dtype=np.uint8)
rgba[:,:,:3] = np.rint(srgb(rgb)*255).astype(np.uint8)
alpha = checked_image("leaf", "_AlphaMap").convert("L")
if alpha.size != (base.shape[1],base.shape[0]):
    raise ValueError("Leaf alpha/base texture dimensions disagree")
rgba[:,:,3] = np.asarray(alpha)
leaf = Image.fromarray(rgba)
trunk = checked_image("trunk", "_BaseMap").convert("RGBA")
output.parent.mkdir(parents=True, exist_ok=True)
leaf.save(output.with_name("pine-leaf-static-palette.png"))
binary, views, accessors = bytearray(), [], []


def append(data, target=None):
    binary.extend(bytes(-len(binary)%4))
    view = {"buffer":0,"byteOffset":len(binary),"byteLength":len(data)}
    if target: view["target"] = target
    views.append(view); binary.extend(data)
    return len(views)-1


def attribute(values, width):
    flat = [x for row in values for x in row]
    view = append(struct.pack("<"+"f"*len(flat),*flat),34962)
    accessors.append({"bufferView":view,"componentType":5126,"count":len(values),"type":f"VEC{width}",
        "min":[min(v[a] for v in values) for a in range(width)],"max":[max(v[a] for v in values) for a in range(width)]})
    return len(accessors)-1


p,n,uv = attribute(positions,3),attribute(normals,3),attribute(uvs,2)
primitives=[]
for material, triangles in enumerate(groups):
    indices=[v for a,b,c in triangles for v in (a,c,b)]
    if any(v < 0 or v >= len(positions) for v in indices): raise ValueError("Invalid source index")
    view=append(struct.pack("<"+"H"*len(indices),*indices),34963)
    accessors.append({"bufferView":view,"componentType":5123,"count":len(indices),"type":"SCALAR"})
    primitives.append({"attributes":{"POSITION":p,"NORMAL":n,"TEXCOORD_0":uv},"indices":len(accessors)-1,"material":material})
images=[]
for image in (leaf,trunk):
    png=io.BytesIO();image.save(png,format="PNG")
    images.append({"bufferView":append(png.getvalue()),"mimeType":"image/png"})
materials=[{"name":"Original pine leaf / static palette QA","doubleSided":True,"alphaMode":"MASK","alphaCutoff":.20000000298023224,
            "pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.8}},
           {"name":"Original pine trunk / static PBR QA","pbrMetallicRoughness":{"baseColorTexture":{"index":1},"metallicFactor":0,"roughnessFactor":.9}}]
document={"asset":{"version":"2.0","generator":"Aniimo Atlas original pine decoder"},"scene":0,"scenes":[{"nodes":[0]}],
          "nodes":[{"mesh":0,"name":mesh.m_Name}],"meshes":[{"primitives":primitives}],"materials":materials,
          "images":images,"textures":[{"source":0},{"source":1}],"bufferViews":views,"accessors":accessors,"buffers":[{"byteLength":len(binary)}]}
text=json.dumps(document,separators=(",",":")).encode();text+=b" "*(-len(text)%4);binary.extend(bytes(-len(binary)%4))
glb=struct.pack("<III",0x46546c67,2,28+len(text)+len(binary))+struct.pack("<II",len(text),0x4e4f534a)+text+struct.pack("<II",len(binary),0x004e4942)+binary
output.write_bytes(glb)
report={"prototypeID":prototype_id,"prefab":definition["name"],"explicitCurrentMesh":definition["meshLODs"][0][0],
        "sourceBundle":source.name,"sourceSHA256":record["sourceSHA256"],"outputSHA256":hashlib.sha256(glb).hexdigest(),
        "vertices":len(positions),"triangles":sum(len(g) for g in groups),"maxGeometryBoundsErrorMetres":max(errors),
        "sourcePositionQuantizationStepMetres":quantization_step,
        "basis":"Unity(z,y,x), reflected triangle winding, flipped V",
        "colorEquation":"linearBaseRGB * (1 + BaseMapA * (2*mix(linearTintPalette,linearLocalTintPalette,0.5)-1))",
        "staticAdaptation":"Palette coordinate0, blend0.5; not live global tint/height/AO. Original alpha used with source cutoff. Roughness constants; original normal/roughness masks, wind/weather/SSS unported."}
output.with_suffix(".provenance.json").write_text(json.dumps(report,indent=2)+"\n")
print("Exported original patched pine",len(positions),"vertices",sum(len(g) for g in groups),"triangles; bounds error",max(errors))
