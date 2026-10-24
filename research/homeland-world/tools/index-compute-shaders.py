#!/usr/bin/env python3
"""Index original compute-shader assets without executing GPU programs."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, output = map(Path, sys.argv[1:3])
rows = []
for path in sorted(root.glob("allshaders_cs_*.uab")):
    environment = UnityPy.load(str(path))
    entries = []
    for obj in environment.objects:
        if obj.type.name == "ComputeShader":
            data = obj.read_typetree()
            entries.append({"name": data.get("m_Name"), "cab": obj.assets_file.name,
                            "pathID": obj.path_id, "keys": list(data)})
    rows.append({"bundle": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                 "shaders": entries})
output.write_text(json.dumps({"bundles": rows}, indent=2) + "\n")
print("Indexed", sum(len(r["shaders"]) for r in rows), "compute shaders in", len(rows), "bundles")
