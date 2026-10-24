#!/usr/bin/env python3
"""Export original XBatch rock/cliff LOD0 meshes with explicit base-layer PBR.

Actual source geometry/UV/normals/material references retained. Topping/detail,
triplanar blending, weather and original roughness shaders are NOT recreated.
"""
from collections import Counter
from functools import lru_cache
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

root,index_path,world_path,output=map(Path,sys.argv[1:5])
output.mkdir(parents=True,exist_ok=True)
world=json.loads(world_path.read_text());table=world["storage"]
index=json.loads(index_path.read_text())
lookup={f["name"].lower():b["bundle"] for b in index["bundles"] for f in b["files"]}
spec=importlib.util.spec_from_file_location("vertex_codec",Path(__file__).with_name("decode-environment-vertices.py"))
codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)
spec=importlib.util.spec_from_file_location("rock_normal_codec",Path(__file__).with_name("decode-rock-normal.py"))
normal_codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(normal_codec)
proof_path=world_path.parent/"rock-shader-verified/manifest.json"
normal_proof=json.loads(proof_path.read_text()) if proof_path.exists() else None
proof_program=None
if normal_proof:
    proof_program=next(p for p in normal_proof["programs"] if p["file"]=="program-p4-s0-v77.dxbc")
    if hashlib.sha256((proof_path.parent/proof_program["file"]).read_bytes()).hexdigest()!=proof_program["sha256"]:
        raise ValueError("Verified primary-normal program changed")
    if hashlib.sha256((root/normal_proof["sourceBundle"]).read_bytes()).hexdigest()!=normal_proof["sourceSHA256"]:
        raise ValueError("Original shader changed since primary-normal verification")
hashes={};snapshots={};material_cache={};texture_cache={}


@lru_cache(maxsize=2)
def bundle(name):
    path=root/name;stat=path.stat();snapshot=(stat.st_size,stat.st_mtime_ns)
    if name in snapshots and snapshot!=snapshots[name]:raise ValueError("Source changed during export")
    environment=UnityPy.load(str(path))
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    if name in hashes and hashes[name]!=digest:raise ValueError("Source hash changed")
    if (path.stat().st_size,path.stat().st_mtime_ns)!=snapshot:raise ValueError("Source changed during read")
    snapshots[name]=snapshot;hashes[name]=digest
    return {(o.assets_file.name.lower(),o.path_id):o for o in environment.objects}


def object_for(cab,path_id,expected_hash=None):
    name=lookup[cab.lower()];objects=bundle(name)
    if expected_hash is not None and hashes[name]!=expected_hash:raise ValueError("Indexed source hash changed")
    return objects[(cab.lower(),path_id)],name


def texture_image(cab,path_id):
    key=(cab.lower(),path_id)
    if key in texture_cache:return texture_cache[key]
    obj,name=object_for(cab,path_id)
    if obj.type.name!="Texture2D":raise ValueError("Expected original Texture2D")
    texture=obj.read();image=texture.image
    filename=f"texture-{len(texture_cache)}-source.png";image.save(output/filename)
    result=(image,{"sourceBundle":name,"sourceSHA256":hashes[name],"sourceCAB":cab,"pathID":path_id,
                   "name":texture.m_Name,"sourceTextureFormat":texture.m_TextureFormat,
                   "file":filename,"sha256":hashlib.sha256((output/filename).read_bytes()).hexdigest()})
    texture_cache[key]=result
    return result


def material_for(asset):
    path=asset["path"]
    if path in material_cache:return material_cache[path]
    ref=asset["indexedSource"];obj,name=object_for(ref["cab"],ref["pathID"],ref["sourceSHA256"])
    if obj.type.name!="Material":raise ValueError("Expected source material")
    data=obj.read_typetree();saved=data["m_SavedProperties"]
    colors=dict(saved["m_Colors"]);texenv=dict(saved["m_TexEnvs"])
    role="_BaseLayer_BaseMap" if "_BaseLayer_BaseMap" in texenv else "_BaseMap" if "_BaseMap" in texenv else None
    image=None;texture=None
    if role:
        pointer=texenv[role]["m_Texture"]
        if pointer["m_PathID"]:
            cab=(obj.assets_file.externals[pointer["m_FileID"]-1].path.split("/")[-1]
                 if pointer["m_FileID"] else obj.assets_file.name)
            original,texture=texture_image(cab,pointer["m_PathID"])
            # Opaque rock RGB is color; original A can be packed height/mask data.
            # Preserve original image above, but never let it become GLB transparency.
            image=original.convert("RGB")
    color=colors.get("_BaseLayer_BaseColor",colors.get("_BaseColor",{"r":1,"g":1,"b":1,"a":1}))
    factor=[color[a] for a in "rgb"]+[1]
    pbr={"baseColorFactor":factor,"metallicFactor":0,"roughnessFactor":.9}
    definition={"name":data["m_Name"]+" / base-layer native QA","alphaMode":"OPAQUE","pbrMetallicRoughness":pbr}
    details={"path":path,"sourceBundle":name,"sourceSHA256":hashes[name],"sourceCAB":obj.assets_file.name,
             "pathID":obj.path_id,"originalProperties":saved,"validKeywords":data.get("m_ValidKeywords"),
             "baseTextureRole":role,"baseTexture":texture,
             "adaptation":"Original primary RGB/base factor, opaque alpha, fixed roughness0.9. Other shader layers/normal/masks preserved as metadata, unported."}
    normal_image=None
    shader=data["m_Shader"]
    shader_cab=(obj.assets_file.externals[shader["m_FileID"]-1].path.split("/")[-1]
                if shader["m_FileID"] else obj.assets_file.name)
    if normal_proof and shader_cab.lower()==normal_proof["sourceCAB"].lower() and shader["m_PathID"]==normal_proof["pathID"] and "_BaseLayer_NormalMap" in texenv:
        normal_ref=texenv["_BaseLayer_NormalMap"]
        if normal_ref["m_Scale"]!={"x":1.,"y":1.} or normal_ref["m_Offset"]!={"x":0.,"y":0.}:
            raise ValueError("Nonidentity primary normal UV transform needs explicit support")
        pointer=normal_ref["m_Texture"]
        if pointer["m_PathID"]:
            normal_cab=(obj.assets_file.externals[pointer["m_FileID"]-1].path.split("/")[-1]
                        if pointer["m_FileID"] else obj.assets_file.name)
            packed,normal_source=texture_image(normal_cab,pointer["m_PathID"])
            normal_scale=dict(saved["m_Floats"]).get("_BaseLayer_NormalScale",1)
            normal_image=normal_codec.decode_image(packed,normal_scale)
            normal_file=f"normal-{len(material_cache)}-decoded.png";normal_image.save(output/normal_file)
            details["primaryNormal"]={"source":normal_source,"scale":normal_scale,"file":normal_file,
                "sha256":hashlib.sha256((output/normal_file).read_bytes()).hexdigest(),
                "proofProgram":"rock-shader-verified/program-p4-s0-v77.dxbc",
                "proofProgramSHA256":proof_program["sha256"],"sourceShaderSHA256":normal_proof["sourceSHA256"],
                "formula":"X=2*R*A-1,Y=2*G-1,Z=sqrt(1-saturate(X²+Y²)); scaleXY,normalize; negateY for flipped glTF V"}
            details["adaptation"]="Original primary RGB/base factor and shader-decoded primary normal. Fixed roughness0.9; topping/detail/weather layers unported."
    if role:details["originalUVTransform"]=texenv[role]
    material_cache[path]=(definition,image,normal_image,details)
    return material_cache[path]


def glb_mesh(mesh,material_assets):
    handler=MeshHandler(mesh);handler.process()
    channels=mesh.m_VertexData.m_Channels
    compressed=channels[0].format==8 and channels[0].dimension==4
    positions=[];normals=[];uvs=[];unity_positions=[]
    for p,n,uv in zip(handler.m_Vertices,handler.m_Normals,handler.m_UV0):
        if compressed:xyz,normal,texcoord=codec.decode(p,n,uv)
        elif channels[0].format==0 and len(p)>=3 and len(n)>=3:
            xyz=list(p[:3]);normal=list(n[:3]);texcoord=list(uv[:2])
        else:raise ValueError("Unverified source vertex representation")
        if any(not math.isfinite(v) for v in xyz+normal+texcoord):raise ValueError("Nonfinite original vertex")
        unity_positions.append(xyz);positions.append([xyz[2],xyz[1],xyz[0]])
        normals.append([normal[2],normal[1],normal[0]]);uvs.append([texcoord[0],1-texcoord[1]])
    if len(positions)!=mesh.m_VertexData.m_VertexCount or not positions:raise ValueError("Incomplete source vertices")
    errors=[]
    for axis,key in enumerate("xyz"):
        low,high=min(p[axis] for p in unity_positions),max(p[axis] for p in unity_positions)
        errors.extend([abs((low+high)/2-getattr(mesh.m_LocalAABB.m_Center,key)),abs((high-low)/2-getattr(mesh.m_LocalAABB.m_Extent,key))])
    step=max(2*(1 << (3+((p[3] >> 1)&7)))/65535 for p in handler.m_Vertices) if compressed else .0001
    if max(errors)>step*1.01:raise ValueError(f"Original mesh AABB mismatch {max(errors)} > {step}")
    groups=handler.get_triangles()
    if len(groups)!=len(material_assets):raise ValueError("Original submesh/material slot disagreement")
    binary=bytearray();views=[];accessors=[];images=[];textures=[];materials=[];details=[]

    def append(data,target=None):
        binary.extend(bytes(-len(binary)%4));view={"buffer":0,"byteOffset":len(binary),"byteLength":len(data)}
        if target:view["target"]=target
        views.append(view);binary.extend(data);return len(views)-1

    def attribute(values,width):
        flat=[v for row in values for v in row]
        view=append(struct.pack("<"+"f"*len(flat),*flat),34962)
        accessors.append({"bufferView":view,"componentType":5126,"count":len(values),"type":f"VEC{width}",
                          "min":[min(row[a] for row in values) for a in range(width)],"max":[max(row[a] for row in values) for a in range(width)]})
        return len(accessors)-1

    pos,normal,uv=attribute(positions,3),attribute(normals,3),attribute(uvs,2)
    for asset in material_assets:
        definition,image,normal_image,detail=material_for(asset)
        definition=json.loads(json.dumps(definition))
        if image:
            png=io.BytesIO();image.save(png,format="PNG")
            images.append({"bufferView":append(png.getvalue()),"mimeType":"image/png"})
            textures.append({"source":len(images)-1})
            definition["pbrMetallicRoughness"]["baseColorTexture"]={"index":len(textures)-1}
        if normal_image:
            png=io.BytesIO();normal_image.save(png,format="PNG")
            images.append({"bufferView":append(png.getvalue()),"mimeType":"image/png"})
            textures.append({"source":len(images)-1})
            definition["normalTexture"]={"index":len(textures)-1,"scale":1}
        materials.append(definition);details.append(detail)
    primitives=[]
    for slot,triangles in enumerate(groups):
        indices=[v for a,b,c in triangles for v in (a,c,b)]
        if any(v<0 or v>=len(positions) for v in indices):raise ValueError("Invalid original mesh index")
        view=append(struct.pack("<"+"I"*len(indices),*indices),34963)
        accessors.append({"bufferView":view,"componentType":5125,"count":len(indices),"type":"SCALAR"})
        primitives.append({"attributes":{"POSITION":pos,"NORMAL":normal,"TEXCOORD_0":uv},"indices":len(accessors)-1,"material":slot})
    doc={"asset":{"version":"2.0","generator":"Aniimo Atlas original static-world mesh exporter"},"scene":0,
         "scenes":[{"nodes":[0]}],"nodes":[{"mesh":0,"name":mesh.m_Name}],"meshes":[{"primitives":primitives}],
         "materials":materials,"images":images,"textures":textures,"bufferViews":views,"accessors":accessors,"buffers":[{"byteLength":len(binary)}]}
    text=json.dumps(doc,separators=(",",":")).encode();text+=b" "*(-len(text)%4);binary.extend(bytes(-len(binary)%4))
    data=struct.pack("<III",0x46546c67,2,28+len(text)+len(binary))+struct.pack("<II",len(text),0x4e4f534a)+text+struct.pack("<II",len(binary),0x004e4942)+binary
    return data,{"vertices":len(positions),"triangles":sum(len(t) for t in groups),"compressed":compressed,
                 "maxBoundsErrorMetres":max(errors),"sourceQuantizationStepMetres":step,"materials":details}


models=[];failures=[];ids=set()
for prototype in table["prototypes"]:
    lod=prototype["lods"][0];renderers=table["renderers"][lod["rendererStart"]:lod["rendererStart"]+lod["rendererCount"]]
    if not any(any(tag in r["mesh"]["path"] for tag in ("Rock","Cliff","Stone")) for r in renderers):continue
    entries=[]
    for ordinal,renderer in enumerate(renderers):
        try:
            ref=renderer["mesh"]["indexedSource"]
            obj,name=object_for(ref["cab"],ref["pathID"],ref["sourceSHA256"])
            if obj.type.name!="Mesh":raise ValueError("Expected source Mesh")
            mesh=obj.read();data,qa=glb_mesh(mesh,renderer["materials"])
            filename=f'prototype-{prototype["id"]}-renderer-{ordinal}.glb';(output/filename).write_bytes(data)
            entries.append({"file":filename,"sha256":hashlib.sha256(data).hexdigest(),"localMatrix":renderer["localMatrix"],
                            "sourceMesh":renderer["mesh"],"geometryQA":qa})
            print("Exported",prototype["id"],mesh.m_Name,qa["vertices"],flush=True)
        except Exception as error:
            failures.append({"prototypeID":prototype["id"],"renderer":ordinal,"error":str(error)})
            break
    if len(entries)==len(renderers):models.append({"prototypeID":prototype["id"],"renderers":entries});ids.add(prototype["id"])
placements=[p for p in world["uniqueInstances"] if p["prototypeID"] in ids]
report={"schema":"original-static-rock-models-v1","sourceWorldSHA256":hashlib.sha256(world_path.read_bytes()).hexdigest(),
        "coordinateBasis":"Unity(z,y,x); reflected winding; flipped V; apply C*localMatrix*C and scale(z,y,x)",
        "models":models,"placements":placements,"failedRenderers":failures,"sourceBundleSHA256":hashes,
        "fidelity":"Original geometry/source primary color and verified EV_TintRock primary normals where shader pointer matches. Layered topping/detail/weather shading not ported."}
(output/"manifest.json").write_text(json.dumps(report,indent=2)+"\n")
print("Complete prototypes",len(models),"unique placements",len(placements),"failed renderers",len(failures))
