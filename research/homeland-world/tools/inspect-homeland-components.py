#!/usr/bin/env python3
"""Summarize only the exact Homeland scene's component schemas and bindings."""
import json
from pathlib import Path
import sys
import UnityPy

root, output = Path(sys.argv[1]), Path(sys.argv[2])
bundle = next(root.glob("mres_level_exunity_1_*.uab"))
env = UnityPy.load(str(bundle))
pointer = env.container[next(key for key in env.container if key.endswith("RuntimeLevel_FB_Home_01.unity"))]
name = pointer.assetsfile.name.removesuffix(".sharedAssets")
file = next(file for bundle in env.files.values() for key, file in bundle.files.items() if key == name)
records = []
for reader in file.objects.values():
    if reader.type.name != "MonoBehaviour":
        continue
    tree = reader.read_typetree()
    game_name = None
    game = tree.get("m_GameObject", {})
    if game.get("m_FileID") == 0 and game.get("m_PathID") in file.objects:
        game_name = file.objects[game["m_PathID"]].read_typetree().get("m_Name")
    record = {"pathID": reader.path_id, "gameObject": game_name, "fields": list(tree),
              "scalars": {}, "bindings": {}, "collections": {}}
    for key, value in tree.items():
        if isinstance(value, (int, float, str, bool)):
            record["scalars"][key] = value
        elif isinstance(value, dict) and "m_PathID" in value and "m_FileID" in value:
            record["bindings"][key] = value
        elif isinstance(value, list):
            record["collections"][key] = {"count": len(value)}
        elif isinstance(value, dict):
            record["collections"][key] = {"fields": list(value)}
            if key == "serializationData":
                record["collections"][key]["byteCount"] = len(value.get("SerializedBytes", []))
                record["collections"][key]["unityReferenceCount"] = len(value.get("ReferencedUnityObjects", []))
    records.append(record)
output.write_text(json.dumps({"sourceBundle": bundle.name, "sourceFile": name,
    "externalFiles": [item.path for item in file.externals], "components": records}, indent=2) + "\n")
print("Saved", len(records), "exact Homeland component schemas", flush=True)
