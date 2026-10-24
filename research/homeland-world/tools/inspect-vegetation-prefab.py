#!/usr/bin/env python3
"""Inspect one referenced original vegetation prefab, with bounded traversal."""
import json
from pathlib import Path
import sys
import UnityPy

root, index_path, references_path = map(Path, sys.argv[1:4])
reference_index, output = int(sys.argv[4]), Path(sys.argv[5])
index = json.loads(index_path.read_text())
references = json.loads(references_path.read_text())
lookup = {}
for bundle in index["bundles"]:
    for item in bundle["files"]:
        if item["name"].lower() in lookup:
            raise ValueError("Ambiguous resource filename")
        lookup[item["name"].lower()] = bundle["bundle"]
reference = references["unityReferences"][reference_index]
if reference["m_FileID"] <= 0:
    raise ValueError("This inspector expects an external prefab")
cab = references["externalFiles"][reference["m_FileID"] - 1].split("/")[-1]
bundle_name = lookup[cab.lower()]
environment = UnityPy.load(str(root / bundle_name))
file = next(file for bundle in environment.files.values() for name, file in bundle.files.items() if name.lower() == cab.lower())
visited = set()


def game_object(path_id, depth):
    if depth > 8 or len(visited) >= 256 or path_id in visited:
        raise ValueError("Prefab hierarchy exceeds bound or is cyclic")
    visited.add(path_id)
    reader = file.objects[path_id]
    data = reader.read_typetree()
    result = {"name": data["m_Name"], "pathID": path_id, "components": [], "children": []}
    for pointer in data["m_Component"]:
        component = file.objects[pointer["component"]["m_PathID"]]
        tree = component.read_typetree()
        result["components"].append({"pathID": component.path_id, "type": component.type.name, "data": tree})
        if component.type.name == "Transform":
            for child in tree["m_Children"]:
                if child["m_FileID"] != 0:
                    raise ValueError("External child transform unsupported")
                transform = file.objects[child["m_PathID"]].read_typetree()
                result["children"].append(game_object(transform["m_GameObject"]["m_PathID"], depth + 1))
    return result


result = {"prefabIndex": reference_index, "sourceBundle": bundle_name, "sourceCAB": cab,
          "externalFiles": [item.path for item in file.externals],
          "root": game_object(reference["m_PathID"], 0)}
output.write_text(json.dumps(result, indent=2) + "\n")
print("Inspected", result["root"]["name"], "nodes", len(visited), flush=True)
