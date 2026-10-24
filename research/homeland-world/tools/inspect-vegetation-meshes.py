#!/usr/bin/env python3
"""Resolve original vegetation LOD geometry metadata against build-pinned indexes."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, indexes, definitions_path, output = map(Path, sys.argv[1:5])
definitions = json.loads(definitions_path.read_text())
wanted = {p for d in definitions["prototypes"] for lod in d["meshLODs"] for p in lod}
resolved, missing = {}, set(wanted)
for index_file in sorted(indexes.glob("*.json")):
    index = json.loads(index_file.read_text())
    entries = [entry for entry in index["assets"] if entry["path"] in wanted]
    if not entries:
        continue
    path = root / index["bundle"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != index["sha256"]:
        raise ValueError("Bundle changed since indexing")
    environment = UnityPy.load(str(path))
    readers = {(obj.assets_file.name.lower(), obj.path_id): obj for obj in environment.objects}
    for entry in entries:
        if entry["path"] in resolved:
            raise ValueError("Ambiguous asset path")
        obj = readers[(entry["cab"].lower(), entry["pathID"])]
        if obj.type.name != "Mesh":
            raise ValueError("Expected mesh")
        data = obj.read_typetree()
        resolved[entry["path"]] = {**entry, "sourceBundle": path.name, "sourceSHA256": index["sha256"],
            "name": data["m_Name"], "bounds": data["m_LocalAABB"],
            "subMeshes": data["m_SubMeshes"], "indexFormat": data.get("m_IndexFormat"),
            "vertexCount": data["m_VertexData"]["m_VertexCount"],
            "channels": data["m_VertexData"]["m_Channels"]}
        missing.remove(entry["path"])
    print("Resolved", len(entries), "meshes from", path.name, flush=True)
output.write_text(json.dumps({"meshes": resolved, "missing": sorted(missing)}, indent=2) + "\n")
print("Total", len(resolved), "missing", len(missing))
