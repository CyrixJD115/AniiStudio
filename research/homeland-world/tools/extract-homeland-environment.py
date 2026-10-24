#!/usr/bin/env python3
"""Read selected installed Unity textures into a local Atlas environment cache.

Usage: extract-homeland-environment.py BUNDLE_DIRECTORY OUTPUT_DIRECTORY
Requires UnityPy. Never modifies the game and never uploads extracted assets.
The manifest records original names and bundle hashes; terrain and layout
reconstruction are separate from these source textures.
"""
import hashlib
import json
import math
from pathlib import Path
import sys
import UnityPy
from PIL import Image


def daylight_faces(output):
    """Adapt packed cloud coverage/highlight to an ordinary native cubemap.

    These are preview lighting choices, not recovered game weather parameters.
    Keep original packed texture alongside them for later shader matching.
    """
    cloud = Image.open(output / "sky-sunny.png").convert("RGB")
    pixels = cloud.load()
    faces = []
    directions = [lambda u, v: (1, -v, -u), lambda u, v: (-1, -v, u),
                  lambda u, v: (u, 1, v), lambda u, v: (u, -1, -v),
                  lambda u, v: (u, -v, 1), lambda u, v: (-u, -v, -1)]
    size = 256
    for index, direction in enumerate(directions):
        face = Image.new("RGB", (size, size))
        target = face.load()
        for py in range(size):
            for px in range(size):
                x, y, z = direction(2 * (px + 0.5) / size - 1, 2 * (py + 0.5) / size - 1)
                length = math.sqrt(x * x + y * y + z * z)
                x, y, z = x / length, y / length, z / length
                u = (math.atan2(z, x) / (2 * math.pi) + 0.5) % 1
                v = math.acos(max(-1, min(1, y))) / math.pi
                _, highlight, coverage = pixels[int(u * (cloud.width - 1)), int(v * (cloud.height - 1))]
                elevation = max(0, y) ** 0.45
                sky = tuple(a * (1 - elevation) + b * elevation
                            for a, b in zip((183, 213, 231), (57, 123, 202)))
                alpha = coverage / 255 * 0.88 * min(1, max(0, y) * 10)
                shade = 213 + highlight / 255 * 42
                target[px, py] = tuple(round(c * (1 - alpha) + shade * alpha) for c in sky)
        filename = f"daylight-face-{index}.png"
        face.save(output / filename)
        faces.append({"file": filename, "fileSHA256": hashlib.sha256((output / filename).read_bytes()).hexdigest()})
    return faces


def extract(root, output):
    output.mkdir(parents=True, exist_ok=True)
    wanted = {
        "T_Tiling_Terrain_Grass_001_CA": "grass-ground.png",
        "T_Tiling_Terrain_Grass_003_CA": "grass-ground-alternate.png",
        "T_Tiling_Terrain_Grass_001_N": "grass-normal.png",
        "T_Sky_ImageCloud2D_Sunny_C": "sky-sunny.png",
        "T_Sky_ImageCloud2D_Sunny_02_C": "sky-sunny-alternate.png",
    }
    patterns = ["*terrain_grass_tga_0_*.uab", "*texture_sky_tga_0_*.uab"]
    bundles = sorted({p for pattern in patterns for p in root.glob(pattern)})
    entries = []
    for bundle in bundles:
        environment = UnityPy.load(str(bundle))
        for obj in environment.objects:
            if obj.type.name != "Texture2D":
                continue
            texture = obj.read()
            filename = wanted.get(texture.m_Name)
            if filename is None:
                continue
            target = output / filename
            image = texture.image
            if filename.startswith("grass-ground"):
                # CA alpha is packed data, not transparent holes in the ground.
                image = image.convert("RGB")
            image.save(target)
            entry = {
                "name": texture.m_Name, "file": filename,
                "width": texture.m_Width, "height": texture.m_Height,
                "bundle": bundle.name,
                "bundleSHA256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
                "fileSHA256": hashlib.sha256(target.read_bytes()).hexdigest(),
            }
            entries.append(entry)
            print(texture.m_Name, "->", filename, flush=True)
    faces = daylight_faces(output)
    manifest = {"version": 1, "source": "Installed Aniimo UnityFS bundles",
                "scope": "Source textures only; exact Homeland terrain and sky projection unverified",
                "textures": entries, "daylightFaces": faces,
                "daylightInterpretation": "Native preview adaptation: cloud B coverage and G highlight with daylight gradient; original game weather parameters not recovered"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    missing = set(wanted) - {entry["name"] for entry in entries}
    if missing:
        raise RuntimeError("Missing source textures: " + ", ".join(sorted(missing)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    extract(Path(sys.argv[1]), Path(sys.argv[2]))
