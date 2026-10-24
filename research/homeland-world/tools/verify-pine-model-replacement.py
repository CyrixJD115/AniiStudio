#!/usr/bin/env python3
"""Compare old chunk bounds with current explicitly referenced patched pine model.

This is evidence collection, never an override selecting a different visual mesh.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import UnityPy

root, output = map(Path, sys.argv[1:3])
research = Path(__file__).resolve().parent.parent / "Research/2026-10-23"
spec = importlib.util.spec_from_file_location("vegetation_instances", Path(__file__).with_name("decode-vegetation-instances.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
definitions = json.loads((research / "homeland-vegetation-stream-definitions.json").read_text())
prototype = next(p for p in definitions["prototypes"] if p["id"] == 7)
prefab = json.loads((research / "pine-a-prefab-source.json").read_text())
environment = UnityPy.load(str(root / prefab["sourceBundle"]))
objects = {o.path_id: o for o in environment.objects if o.assets_file.name == prefab["sourceCAB"]}
platform = objects[-4624975567174895102].read_typetree()
current_path = platform["m_DefaultConfig"]["m_Lods"][0]["m_Renderers"][0]["m_MeshPath"]["m_Path"]
if current_path != prototype["meshLODs"][0][0] or "SM_Tree_Pine_001_B_LOD0" not in current_path:
    raise ValueError("Current prefab/stream definitions changed")
index = json.loads((research / "environment-asset-index/asrep_environment_mesh_asset_5_1b55b2e39534d35ed999b2d94ba0ea1d.json").read_text())
path = root / index["bundle"]
if hashlib.sha256(path.read_bytes()).hexdigest() != index["sha256"]:
    raise ValueError("Geometry changed since index")
entry = next(e for e in index["assets"] if "SM_Tree_Pine_001_A_LOD0_" in e["path"])
environment = UnityPy.load(str(path))
mesh = next(o for o in environment.objects if o.path_id == entry["pathID"]).read_typetree()
original = mesh["m_LocalAABB"]
legacy_bounds = {"center": [original["m_Center"][a] for a in "xyz"],
                 "extents": [original["m_Extent"][a] for a in "xyz"]}
sections = json.loads((research / "homeland-vegetation-chunk-sections.json").read_text())
reference = {c["file"]: r["instanceBounds"] for c in sections["chunks"] for r in c["records"] if r["id"] == 7}
transforms = json.loads((research / "homeland-vegetation-transforms.json").read_text())
results = []
for row in transforms["chunks"]:
    if row["prototypeID"] != 7 or not row["instances"]:
        continue
    errors = {}
    for name, bounds in (("currentReferencedPineB", prototype["bounds"]), ("legacyPineA", legacy_bounds)):
        pairs = [module.transformed_bounds(i, bounds) for i in row["instances"]]
        low = [min(c[a]-e[a] for c,e in pairs) for a in range(3)]
        high = [max(c[a]+e[a] for c,e in pairs) for a in range(3)]
        expected = reference[row["chunk"]]
        errors[name] = max([abs((low[a]+high[a])/2-expected["center"][a]) for a in range(3)] +
                           [abs((high[a]-low[a])/2-expected["extents"][a]) for a in range(3)])
    results.append({"chunk": row["chunk"], "instances": len(row["instances"]), "boundsErrorMetres": errors})
report = {"currentPrefab": prototype["name"], "explicitCurrentLOD0": current_path,
          "prefabSourceBundle": prefab["sourceBundle"],
          "prefabSourceSHA256": hashlib.sha256((root / prefab["sourceBundle"]).read_bytes()).hexdigest(),
          "legacyMesh": entry, "legacyMeshSourceBundle": index["bundle"],
          "legacyMeshSourceSHA256": index["sha256"], "legacyBounds": legacy_bounds,
          "groups": results, "interpretation": "Current prefab explicitly references Pine B; old chunk bounds strongly match Pine A. Preserve actual current references, do not rescale visual model to fit stale bounds."}
output.write_text(json.dumps(report, indent=2) + "\n")
for name in ("currentReferencedPineB", "legacyPineA"):
    values = sorted(r["boundsErrorMetres"][name] for r in results)
    print(name, "groups", len(values), "median/max", values[len(values)//2], max(values),
          "within5cm", sum(v < 0.05 for v in values))
