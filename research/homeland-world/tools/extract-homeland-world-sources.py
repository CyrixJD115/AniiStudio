#!/usr/bin/env python3
"""Preserve exact Homeland terrain source data; no guessed placement or writes.

Usage: extract-homeland-world-sources.py BUNDLE_DIRECTORY OUTPUT_DIRECTORY
This cache is research input, not an enabled/rendered scenery replacement.
"""
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import UnityPy


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(root, output):
    output.mkdir(parents=True, exist_ok=True)
    bundle = next(root.glob("mexp_level_exall_0_*.uab"))
    env = UnityPy.load(str(bundle))
    report = {"version": 1, "sourceBundle": bundle.name,
              "sourceSHA256": digest(bundle), "terrain": [], "textures": [],
              "status": "Raw source data only; coordinate/height normalization must be verified before rendering"}
    for path, pointer in env.container.items():
        match = re.search(r"EntityLevel_FB_Home_01/.*Terrain_(\d+)_(\d+)_CollisionData.asset$", path)
        if not match:
            continue
        data = pointer.read_typetree()
        heightmap = data["m_Heightmap"]
        resolution = heightmap["m_Resolution"]
        heights = heightmap["m_Heights"]
        if not 2 <= resolution <= 1025 or len(heights) != resolution * resolution:
            raise ValueError("Unexpected source heightmap dimensions")
        x, z = map(int, match.groups())
        filename = f"terrain-{x}-{z}.u16le"
        target = output / filename
        target.write_bytes(struct.pack("<" + "H" * len(heights), *(value & 0xffff for value in heights)))
        hole_name = f"terrain-{x}-{z}.holes-u8"
        (output / hole_name).write_bytes(bytes(heightmap["m_Holes"]))
        report["terrain"].append({"x": x, "z": z, "sourceAsset": path,
            "file": filename, "fileSHA256": digest(target),
            "resolution": resolution, "scale": heightmap["m_Scale"],
            "rawMinimum": min(heights), "rawMaximum": max(heights),
            "holesFile": hole_name, "holesSHA256": digest(output / hole_name)})
    report["terrain"].sort(key=lambda item: (item["x"], item["z"]))
    if len(report["terrain"]) != 64:
        raise ValueError("Expected the source Homeland 8x8 terrain set")

    scene_bundle = next(root.glob("mres_level_exunity_1_*.uab"))
    scene_env = UnityPy.load(str(scene_bundle))
    scene_path = next(path for path in scene_env.container if path.endswith("RuntimeLevel_FB_Home_01.unity"))
    # A scene pointer targets its .sharedAssets file with pathID zero. The
    # matching serialized scene omits that suffix; unrelated scenes coexist in
    # this merged bundle and must not be traversed as Homeland objects.
    scene_pointer = scene_env.container[scene_path]
    shared_file = scene_pointer.assetsfile
    scene_name = shared_file.name.removesuffix(".sharedAssets")
    scene_file = next(file for bundle in scene_env.files.values()
                      for name, file in getattr(bundle, "files", {}).items() if name == scene_name)
    report["sceneBundle"] = scene_bundle.name
    report["sceneBundleSHA256"] = digest(scene_bundle)
    report["sceneAsset"] = scene_path
    report["scenePointer"] = {"fileID": scene_pointer.m_FileID, "pathID": scene_pointer.m_PathID,
                              "serializedFile": scene_file.name}
    report["terrainObjects"] = []
    for obj in scene_file.objects.values():
        if obj.type.name != "Terrain":
            continue
        tree = obj.read_typetree()
        game = scene_file.objects[tree["m_GameObject"]["m_PathID"]].read_typetree()
        transforms = []
        for component in game["m_Component"]:
            reader = scene_file.objects[component["component"]["m_PathID"]]
            if reader.type.name == "Transform":
                current = reader.read_typetree()
                # Preserve the whole parent chain instead of assuming its root
                # is identity or that chunk indices imply world coordinates.
                for _ in range(64):
                    transforms.append({key: current[key] for key in
                        ("m_LocalPosition", "m_LocalRotation", "m_LocalScale")})
                    parent = current["m_Father"]
                    if parent["m_PathID"] == 0:
                        break
                    current = scene_file.objects[parent["m_PathID"]].read_typetree()
                else:
                    raise ValueError("Transform parent chain is cyclic or too deep")
        report["terrainObjects"].append({"name": game["m_Name"],
            "terrainData": tree.get("m_TerrainData"), "transformChain": transforms})
    if len(report["terrainObjects"]) != 64:
        raise ValueError("Exact Homeland scene must contain all64 terrain objects")

    texture_bundle = next(root.glob("mexp_level_extga_0_*.uab"))
    for path, pointer in UnityPy.load(str(texture_bundle)).container.items():
        if "Level_FB_Home_01_ExportGlobalBaseColorMap" not in path:
            continue
        texture = pointer.read()
        filename = "homeland-global-base-color.png"
        target = output / filename
        image = texture.image
        image.save(target)
        rgb_name = "homeland-global-base-color-rgb.png"
        image.convert("RGB").save(output / rgb_name)
        report["textures"].append({"sourceAsset": path, "file": filename,
            "fileSHA256": digest(target), "width": texture.m_Width, "height": texture.m_Height,
            "bundle": texture_bundle.name, "bundleSHA256": digest(texture_bundle),
            "rgbFile": rgb_name, "rgbSHA256": digest(output / rgb_name),
            "rgbInterpretation": "Opaque original RGB; alpha is packed data, not terrain visibility"})
    (output / "sources.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Preserved", len(report["terrain"]), "heightmaps,", len(report["terrainObjects"]),
          "scene terrain records and", len(report["textures"]), "global color maps", flush=True)


if __name__ == "__main__":
    extract(Path(sys.argv[1]), Path(sys.argv[2]))
