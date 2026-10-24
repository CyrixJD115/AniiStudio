#!/usr/bin/env python3
"""Preserve original material texture references/images; packed channels stay raw."""
import hashlib
import json
from pathlib import Path
import re
import sys
import UnityPy

root, index_path, material_path, output = map(Path, sys.argv[1:5])
output.mkdir(parents=True, exist_ok=True)
material = json.loads(material_path.read_text())
index = json.loads(index_path.read_text())
lookup = {f["name"].lower(): b["bundle"] for b in index["bundles"] for f in b["files"]}
rows = []
by_cab = {}
for name, texture in material["data"]["m_SavedProperties"]["m_TexEnvs"]:
    pointer = texture["m_Texture"]
    if not pointer["m_PathID"]:
        continue
    cab = (material["externalFiles"][pointer["m_FileID"]-1].split("/")[-1]
           if pointer["m_FileID"] else material["sourceCAB"])
    by_cab.setdefault(cab, []).append((name, texture))
for cab, textures in by_cab.items():
    path = root / lookup[cab.lower()]
    environment = UnityPy.load(str(path))
    objects = {o.path_id: o for o in environment.objects if o.assets_file.name.lower() == cab.lower()}
    for role, reference in textures:
        obj = objects[reference["m_Texture"]["m_PathID"]]
        if obj.type.name != "Texture2D":
            raise ValueError("Unexpected material texture type")
        texture = obj.read()
        image = texture.image
        filename = re.sub(r"[^A-Za-z0-9_-]", "_", role) + ".png"
        image.save(output / filename)
        rows.append({"role": role, "name": texture.m_Name, "width": image.width, "height": image.height,
                     "format": texture.m_TextureFormat, "mode": image.mode, "extrema": image.getextrema(),
                     "file": filename, "imageSHA256": hashlib.sha256((output / filename).read_bytes()).hexdigest(),
                     "sourceBundle": path.name, "sourceSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
                     "sourceCAB": cab, "pathID": obj.path_id, "reference": reference})
report = {"material": material["data"]["m_Name"], "sourceBundle": material["sourceBundle"],
          "sourceSHA256": hashlib.sha256((root / material["sourceBundle"]).read_bytes()).hexdigest(),
          "textures": rows, "channelInterpretation": "Original image channels preserved; not assumed to be diffuse/normal/alpha semantics until shader verified."}
(output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
print("Preserved", len(rows), "original textures for", report["material"])
