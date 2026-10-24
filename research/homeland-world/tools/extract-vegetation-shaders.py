#!/usr/bin/env python3
"""Preserve selected original compiled shaders for offline format inspection."""
import hashlib
import json
from pathlib import Path
import re
import sys
import UnityPy

root, index_path, output = map(Path, sys.argv[1:4])
output.mkdir(parents=True, exist_ok=True)
index = json.loads(index_path.read_text())
wanted = set(sys.argv[4:]) or {"GenerateBlockAABB", "CalculateAABB", "GeneratePointCloud", "InstanceCull", "VegetationUtil"}
results = []
for bundle in index["bundles"]:
    shaders = [s for s in bundle["shaders"] if s["name"] in wanted]
    if not shaders:
        continue
    path = root / bundle["bundle"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != bundle["sha256"]:
        raise ValueError("Source changed since index")
    environment = UnityPy.load(str(path))
    for obj in environment.objects:
        if obj.type.name != "ComputeShader":
            continue
        data = obj.read_typetree()
        if data.get("m_Name") not in wanted:
            continue
        variant = next(v for v in data["variants"] if v["targetRenderer"] == 2)
        kernels = []
        for i, kernel in enumerate(variant["kernels"]):
            for j, program in enumerate(kernel["uniqueVariants"]):
                if not re.fullmatch(r"[A-Za-z0-9_]+", kernel["name"]):
                    raise ValueError("Unsafe kernel filename")
                code = bytes(program["code"])
                if code[:4] != b"DXBC":
                    raise ValueError("Unexpected program container")
                filename = f'{data["m_Name"]}-{i}-{kernel["name"]}-{j}.dxbc'
                (output / filename).write_bytes(code)
                kernels.append({"file": filename, "sha256": hashlib.sha256(code).hexdigest(),
                                "bytes": len(code), "metadata": {k: v for k, v in program.items() if k != "code"}})
        results.append({"shader": data["m_Name"], "bundle": path.name, "sourceSHA256": bundle["sha256"],
                        "pathID": obj.path_id, "renderer": 2, "constantBuffers": variant["constantBuffers"],
                        "kernels": kernels})
(output / "manifest.json").write_text(json.dumps({"shaders": results}, indent=2) + "\n")
print("Preserved", sum(len(s["kernels"]) for s in results), "offline shader programs")
