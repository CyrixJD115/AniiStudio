#!/usr/bin/env python3
"""Resolve the exact Homeland runtime render-root asset via CAB metadata."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, index_path, output = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
output.mkdir(parents=True, exist_ok=True)
index = json.loads(index_path.read_text())
lookup = {}
for bundle in index["bundles"]:
    for entry in bundle["files"]:
        key = entry["name"].lower()
        if key in lookup:
            raise ValueError("Ambiguous internal resource name")
        lookup[key] = bundle["bundle"]

scene_bundle = next(root.glob("mres_level_exunity_1_*.uab"))
environment = UnityPy.load(str(scene_bundle))
pointer = environment.container[next(key for key in environment.container if key.endswith("RuntimeLevel_FB_Home_01.unity"))]
scene_name = pointer.assetsfile.name.removesuffix(".sharedAssets")
scene_file = next(file for bundle in environment.files.values() for name, file in bundle.files.items() if name == scene_name)
matches = []
for reader in scene_file.objects.values():
    if reader.type.name != "MonoBehaviour":
        continue
    tree = reader.read_typetree()
    if "m_RootAssetPathRaw" not in tree:
        continue
    reference = tree["m_RootAsset"]
    if reference["m_PathID"] == 0:
        continue
    if reference["m_FileID"] == 0:
        file = scene_file
        bundle_path = scene_bundle
    else:
        cab = scene_file.externals[reference["m_FileID"] - 1].path.split("/")[-1]
        bundle_path = root / lookup[cab.lower()]
        asset_env = UnityPy.load(str(bundle_path))
        file = next(file for bundle in asset_env.files.values() for name, file in bundle.files.items() if name.lower() == cab.lower())
    asset = file.objects[reference["m_PathID"]]
    report = {"componentPathID": reader.path_id, "componentFields": {key: value for key, value in tree.items() if key != "serializationData"},
              "assetType": asset.type.name, "bundle": bundle_path.name,
              "bundleSHA256": hashlib.sha256(bundle_path.read_bytes()).hexdigest(), "pathID": asset.path_id}
    if asset.type.name == "TextAsset":
        data = asset.read().m_Script
        if isinstance(data, str):
            data = data.encode("utf-8", "surrogateescape")
        if len(data) > 64 * 1024 * 1024:
            raise ValueError("Render-root text asset exceeds inspection bound")
        filename = "homeland-render-root.bin"
        (output / filename).write_bytes(data)
        report.update(file=filename, bytes=len(data), fileSHA256=hashlib.sha256(data).hexdigest(), first32Bytes=data[:32].hex())
    else:
        data = asset.read_typetree()
        filename = "homeland-render-root-object.json"
        (output / filename).write_text(json.dumps(data, indent=2))
        report.update(file=filename, objectKeys=list(data))
    matches.append(report)
if len(matches) != 1:
    raise ValueError(f"Expected one exact Homeland render root, got {len(matches)}")
(output / "render-root-source.json").write_text(json.dumps(matches[0], indent=2) + "\n")
print("Resolved Homeland root", matches[0]["assetType"], matches[0].get("bytes", "structured"), "bytes", flush=True)
