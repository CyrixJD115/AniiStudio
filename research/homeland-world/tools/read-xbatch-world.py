#!/usr/bin/env python3
"""Bounded static XBatch storage/packet reader. Never reads/writes player saves.

Keeps undecoded render flags opaque. Resolves explicit mesh/material paths and
deduplicates repeated culling-cell copies only when prototype and bytes agree.
"""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import sys


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader_module = load("xbatch_reader", "read-vegetation-storage.py")
stream = load("xbatch_stream", "read-xrender-stream.py")


def storage(data):
    r = reader_module.Reader(data)
    tag = r.number("B")
    if tag != 1:
        raise ValueError("Unsupported observed storage layout tag")
    pack_path = r.string()
    if not pack_path.endswith("/XBatch/XBatch.pack") or ".." in pack_path.split("/"):
        raise ValueError("Unexpected static packet path")
    header = [r.number("I") for _ in range(15)]
    prototypes = []
    for identity in range(r.count(4096)):
        offset = r.pos
        distances = r.floats(r.count(16))
        bounds = {"center":r.floats(3),"extents":r.floats(3)}
        size = r.number("f")
        opaque = {"words":[r.number("I"),r.number("I")],"byte":r.number("B"),
                  "signedWords":[r.number("i") for _ in range(4)]}
        lods = [{"rendererStart":r.number("I"),"rendererCount":r.count(256),"materialCount":r.count(256)}
                for _ in range(r.count(16))]
        first_renderer, material_count = r.number("I"),r.count(4096)
        if len(distances) != len(lods) or not lods or first_renderer != lods[0]["rendererStart"] or material_count != sum(l["materialCount"] for l in lods):
            raise ValueError("Prototype LOD table crosscheck failed")
        prototypes.append({"id":identity,"offset":offset,"lodDistances":distances,"bounds":bounds,
                           "objectSize":size,"opaqueMetadata":opaque,"lods":lods,
                           "firstRenderer":first_renderer,"materialCount":material_count})
    renderers = []
    for _ in range(r.count(16384)):
        renderers.append({"localMatrix":r.floats(16),"opaqueRenderFlags":r.number("I"),
                          "meshIndex":r.number("I"),"materialStart":r.number("I"),"materialCount":r.count(256)})
    material_indices = [r.number("I") for _ in range(r.count(65536))]
    assets = {}
    for role in ("meshes","materials"):
        assets[role] = [{"builtIn":r.boolean(),"path":r.string()} for _ in range(r.count(16384))]
    packet_ids = [r.number("I") for _ in range(r.count(65536))]
    if r.pos != len(data) or len(packet_ids) != len(set(packet_ids)):
        raise ValueError("Unparsed storage bytes or repeated packet ID")
    renderer_coverage = []
    for prototype in prototypes:
        for lod in prototype["lods"]:
            start,end=lod["rendererStart"],lod["rendererStart"]+lod["rendererCount"]
            if end > len(renderers) or sum(x["materialCount"] for x in renderers[start:end]) != lod["materialCount"]:
                raise ValueError("LOD renderer/material span mismatch")
            renderer_coverage.extend(range(start,end))
    if sorted(renderer_coverage) != list(range(len(renderers))):
        raise ValueError("LODs do not partition renderer table")
    material_coverage = []
    for renderer in renderers:
        start,end=renderer["materialStart"],renderer["materialStart"]+renderer["materialCount"]
        if renderer["meshIndex"] >= len(assets["meshes"]) or end > len(material_indices):
            raise ValueError("Renderer references out-of-range resource")
        material_coverage.extend(range(start,end))
        renderer["mesh"] = assets["meshes"][renderer["meshIndex"]]
        indices=material_indices[start:end]
        if any(i >= len(assets["materials"]) for i in indices):
            raise ValueError("Material reference out of range")
        renderer["materials"] = [assets["materials"][i] for i in indices]
    if sorted(material_coverage) != list(range(len(material_indices))):
        raise ValueError("Renderer material spans do not partition flat material table")
    return {"layoutTag":tag,"packPath":pack_path,"opaqueHeaderWords":header,"prototypes":prototypes,
            "renderers":renderers,"materialIndices":material_indices,**assets,"packetIDs":packet_ids,
            "bytesConsumed":r.pos,"decodedSHA256":hashlib.sha256(data).hexdigest()}


def packet(data):
    r = reader_module.Reader(data)
    byte_length = r.count(1024*1024)
    if byte_length % 12:
        raise ValueError("Draw span byte count must divide by12")
    draws = [{"prototypeID":r.number("I"),"first":r.number("I"),"count":r.count(65536)}
             for _ in range(byte_length//12)]
    instance_bytes = r.count(16*1024*1024)
    if instance_bytes % 48:
        raise ValueError("Instance buffer must divide by48")
    instances = []
    for _ in range(instance_bytes//48):
        offset=r.pos
        p,q,s = r.floats(4),r.floats(4),r.floats(3)
        identity = r.number("I")
        if p[3] != 1 or abs(sum(v*v for v in q)-1)>1e-4 or any(v==0 for v in s):
            raise ValueError("Invalid source affine transform")
        instances.append({"sourceInstanceID":identity,"position":p[:3],"positionW":p[3],
                          "rotationXYZW":q,"scale":s,"encodedHex":data[offset:r.pos].hex()})
    bounds = {"center":r.floats(3),"extents":r.floats(3)}
    if r.pos != len(data):
        raise ValueError("Unparsed packet tail")
    coverage=[]
    for draw in draws:
        start,end=draw["first"],draw["first"]+draw["count"]
        if end > len(instances):raise ValueError("Draw span exceeds instance buffer")
        coverage.extend(range(start,end))
        for instance in instances[start:end]:instance["prototypeID"]=draw["prototypeID"]
    if sorted(coverage) != list(range(len(instances))):
        raise ValueError("Draw spans do not partition instance buffer")
    return {"draws":draws,"instances":instances,"bounds":bounds}


def unique_instances(packets, prototype_count):
    unique={}
    for packet_id, row in packets.items():
        for instance in row["instances"]:
            if instance["prototypeID"] >= prototype_count:
                raise ValueError("Unknown static prototype ID")
            identity=instance["sourceInstanceID"]
            if identity in unique:
                original=unique[identity]
                if original["prototypeID"] != instance["prototypeID"] or original["encodedHex"] != instance["encodedHex"]:
                    raise ValueError("Conflicting copies of static instance ID")
                original["packetCopies"].append(packet_id)
            else:unique[identity]={**instance,"packetCopies":[packet_id]}
    return [unique[k] for k in sorted(unique)]


def bind_resources(table, refs, by_path):
    reference_rows=refs["data"]["m_Reference"]
    all_assets=table["materials"]+table["meshes"]
    if len(all_assets)!=len(reference_rows):raise ValueError("Unity reference count mismatch")
    checked,missing=0,[]
    for i,(asset,reference) in enumerate(zip(all_assets,reference_rows)):
        candidates=by_path.get(asset["path"])
        if candidates is None:missing.append(asset["path"]);continue
        if not 1 <= reference["m_FileID"] <= len(refs["externalFiles"]):
            raise ValueError("Unsupported independent reference scope")
        cab=refs["externalFiles"][reference["m_FileID"]-1].split("/")[-1]
        candidates=candidates if isinstance(candidates,list) else [candidates]
        matching=[c for c in candidates if cab.lower()==c["cab"].lower() and reference["m_PathID"]==c["pathID"]]
        if not matching:
            raise ValueError("Storage asset path disagrees with independent Unity reference")
        if len({c.get("sourceBundle") for c in matching})>1:
            raise ValueError("Ambiguous source bundles for independently referenced object")
        resolved=matching[0]
        asset["indexedSource"]=resolved;asset["unityReferenceIndex"]=i;checked+=1
    return checked,missing


if __name__ == "__main__":
    root, references_path, indexes, output = map(Path,sys.argv[1:5])
    storage_source=root/"XBatch/XBatchStorage.bin";packet_source=root/"XBatch/XBatch.pack"
    storage_raw,packet_raw=storage_source.read_bytes(),packet_source.read_bytes()
    stored=stream.decode(storage_raw)
    if len(stored)!=1:raise ValueError("Expected one storage record")
    table=storage(stored[0]["bytes"])
    packets={e["id"]:packet(e["bytes"]) for e in stream.decode(packet_raw)}
    if set(packets)!=set(table["packetIDs"]):raise ValueError("Storage/packet directory mismatch")
    instances=unique_instances(packets,len(table["prototypes"]))
    refs=json.loads(references_path.read_text())["XBatchReference"]
    by_path={}
    for path in indexes.glob("*.json"):
        index=json.loads(path.read_text())
        for asset in index["assets"]:
            by_path.setdefault(asset["path"],[]).append({**asset,"sourceBundle":index["bundle"],"sourceSHA256":index["sha256"]})
    checked,missing=bind_resources(table,refs,by_path)
    report={"schema":"original-static-xbatch-world-v1","storageSourceSHA256":hashlib.sha256(storage_raw).hexdigest(),
            "packetSourceSHA256":hashlib.sha256(packet_raw).hexdigest(),"storage":table,
            "packetCount":len(packets),"packetInstanceCopies":sum(len(p["instances"]) for p in packets.values()),
            "uniqueInstances":instances,"independentUnityReferencesChecked":checked,"unindexedAssets":missing,
            "scope":"Static scenery only; original local renderer matrices and nonuniform instance scales preserved. Not player/save object IDs."}
    output.write_text(json.dumps(report,indent=2)+"\n")
    print("Prototypes",len(table["prototypes"]),"renderers",len(table["renderers"]),"unique static instances",len(instances),
          "copies",report["packetInstanceCopies"],"independent refs checked",checked,"unindexed",len(missing))
