#!/usr/bin/env python3
"""Read the exact Homeland collider-root metadata, without changing the game."""
from pathlib import Path
import json
import sys
import UnityPy

root = Path(sys.argv[1])
bundle = next(root.glob("ares_level_runtime_prefab_0_*.uab"))
environment = UnityPy.load(str(bundle))
key = next(key for key in environment.container if "RuntimeLevel_FB_Home_01_MeshColliderRef" in key)
reader = environment.container[key].deref()
file = reader.assets_file
game_object = reader.read_typetree()
report = {"bundle": bundle.name, "container": key, "root": game_object,
          "externals": [item.path for item in file.externals], "components": []}
for component in game_object["m_Component"]:
    obj = file.objects[component["component"]["m_PathID"]]
    tree = obj.read_typetree()
    entry = {"type": obj.type.name, "data": tree, "sampleChildren": []}
    if obj.type.name == "Transform":
        for child in tree["m_Children"][:5]:
            transform = file.objects[child["m_PathID"]].read_typetree()
            game = file.objects[transform["m_GameObject"]["m_PathID"]].read_typetree()
            components = []
            for ref in game["m_Component"]:
                obj = file.objects[ref["component"]["m_PathID"]]
                components.append({"type": obj.type.name, "data": obj.read_typetree()})
            entry["sampleChildren"].append({"name": game["m_Name"], "components": components})
    report["components"].append(entry)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2))
print("Saved root and sample metadata; children:",
      [len(item["data"].get("m_Children", [])) for item in report["components"]], flush=True)
