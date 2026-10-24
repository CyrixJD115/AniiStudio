#!/usr/bin/env python3
"""Export the original native grass mesh to GLB, with explicit static PBR adaptation.

No invented blades or placement. Original wind/weather/color shader is not ported.
Basis: native (x,y,z) = Unity (z,y,x), reflected winding; glTF V=1-Unity V.
"""
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import struct
import sys
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler
from PIL import Image

root, world, research, output = map(Path, sys.argv[1:5])
spec = importlib.util.spec_from_file_location("vertex_codec", Path(__file__).with_name("decode-environment-vertices.py"))
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)
index = json.loads((research / "environment-asset-index/asrep_environment_mesh_asset_3_4e6542e756ae20aa01400f335bf72cbb.json").read_text())
source = root / index["bundle"]
if hashlib.sha256(source.read_bytes()).hexdigest() != index["sha256"]:
    raise ValueError("Mesh source changed")
environment = UnityPy.load(str(source))
mesh = next(o for o in environment.objects if o.path_id == 267542050239650537).read()
handler = MeshHandler(mesh)
handler.process()
positions, normals, uvs = [], [], []
source_positions = []
for p, n, uv in zip(handler.m_Vertices, handler.m_Normals, handler.m_UV0):
    xyz, normal, texcoord = codec.decode(p, n, uv)
    source_positions.append(xyz)
    positions.append([xyz[2], xyz[1], xyz[0]])
    normals.append([normal[2], normal[1], normal[0]])
    uvs.append([texcoord[0], 1-texcoord[1]])
if len(positions) != 120:
    raise ValueError("Original grass mesh vertex count changed")
bounds = mesh.m_LocalAABB
errors = []
for axis, key in enumerate("xyz"):
    low = min(p[axis] for p in source_positions)
    high = max(p[axis] for p in source_positions)
    errors += [abs((low+high)/2-getattr(bounds.m_Center, key)),
               abs((high-low)/2-getattr(bounds.m_Extent, key))]
if max(errors) > 0.0003:
    raise ValueError("Decoded geometry disagrees with original mesh bounds")
groups = handler.get_triangles()
if len(groups) != 1:
    raise ValueError("Grass primitive layout changed")
indices = [i for a,b,c in groups[0] for i in (a,c,b)]
if any(i >= len(positions) for i in indices):
    raise ValueError("Invalid mesh index")
material = json.loads((research / "grass-material-data.json").read_text())["data"]
saved = material["m_SavedProperties"]
floats = dict(saved["m_Floats"])
colors = dict(saved["m_Colors"])
base = colors["_BaseColor"]
alpha_source = world / "original-grass-alpha.png"
alpha = Image.open(alpha_source).convert("L")
rgba = Image.new("RGBA", alpha.size, (255,255,255,255))
rgba.putalpha(alpha)
png = io.BytesIO()
rgba.save(png, format="PNG")
binary = bytearray()
views, accessors = [], []


def append(data, target=None):
    while len(binary) % 4:
        binary.append(0)
    view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
    if target:
        view["target"] = target
    views.append(view)
    binary.extend(data)
    return len(views)-1


def attribute(values, width):
    flat = [v for row in values for v in row]
    view = append(struct.pack("<" + "f"*len(flat), *flat), 34962)
    accessors.append({"bufferView": view, "componentType": 5126, "count": len(values), "type": f"VEC{width}",
                      "min": [min(row[i] for row in values) for i in range(width)],
                      "max": [max(row[i] for row in values) for i in range(width)]})
    return len(accessors)-1


pos, normal, uv = attribute(positions, 3), attribute(normals, 3), attribute(uvs, 2)
iview = append(struct.pack("<" + "H"*len(indices), *indices), 34963)
accessors.append({"bufferView": iview, "componentType": 5123, "count": len(indices), "type": "SCALAR"})
png_view = append(png.getvalue())
document = {"asset": {"version": "2.0", "generator": "Aniimo Atlas original grass decoder"},
            "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": mesh.m_Name}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": pos, "NORMAL": normal, "TEXCOORD_0": uv},
                                         "indices": len(accessors)-1, "material": 0}]}],
            "materials": [{"name": "Original grass alpha / static PBR adaptation", "doubleSided": True,
                           "alphaMode": "MASK", "alphaCutoff": floats["_AlphaCutoff"],
                           "pbrMetallicRoughness": {"baseColorFactor": [base[a] for a in "rgba"],
                               "baseColorTexture": {"index": 0}, "metallicFactor": 0,
                               "roughnessFactor": floats["_Roughness"]}}],
            "textures": [{"source": 0}], "images": [{"bufferView": png_view, "mimeType": "image/png"}],
            "bufferViews": views, "accessors": accessors, "buffers": [{"byteLength": len(binary)}]}
json_bytes = json.dumps(document, separators=(",", ":")).encode()
json_bytes += b" " * (-len(json_bytes) % 4)
binary += bytes(-len(binary) % 4)
total = 12+8+len(json_bytes)+8+len(binary)
glb = struct.pack("<III", 0x46546c67, 2, total) + struct.pack("<II", len(json_bytes), 0x4e4f534a) + json_bytes
glb += struct.pack("<II", len(binary), 0x004e4942) + binary
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(glb)
report = {"mesh": mesh.m_Name, "sourceBundle": source.name, "sourceSHA256": index["sha256"],
          "alphaSHA256": hashlib.sha256(alpha_source.read_bytes()).hexdigest(),
          "outputSHA256": hashlib.sha256(glb).hexdigest(), "vertices": len(positions), "triangles": len(indices)//3,
          "maxSourceBoundsErrorMetres": max(errors), "basis": "Unity(z,y,x); reflected winding; V flipped",
          "materialFidelity": "Static PBR adaptation using original base color, alpha map, cutoff and roughness. Original wind, tip/variation colors, SSS, weather, alpha-growth shader not ported.",
          "originalMaterialProperties": saved}
output.with_suffix(".provenance.json").write_text(json.dumps(report, indent=2) + "\n")
print("Exported", len(positions), "vertices /", len(indices)//3, "triangles; max bounds error", max(errors))
