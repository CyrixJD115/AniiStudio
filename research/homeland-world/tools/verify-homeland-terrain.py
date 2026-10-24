#!/usr/bin/env python3
"""Verify source terrain placement, shared borders and static area heights.

Usage: verify-homeland-terrain.py WORLD_CACHE HOMELAND_AREA_JSON
Outputs evidence only. Does not enable the unintegrated terrain in Atlas.
"""
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

root = Path(sys.argv[1])
source = json.loads((root / "sources.json").read_text())
areas = json.loads(Path(sys.argv[2]).read_text())
tiles = {(item["x"], item["z"]): item for item in source["terrain"]}
if set(tiles) != {(x, z) for x in range(8) for z in range(8)}:
    raise ValueError("Terrain source grid is incomplete or duplicated")
positions = {}
for terrain in source["terrainObjects"]:
    match = re.match(r"Terrain_(\d+)_(\d+)_", terrain["name"])
    if match is None:
        raise ValueError("Unexpected scene terrain name")
    key = tuple(map(int, match.groups()))
    position = [0.0, 0.0, 0.0]
    for transform in terrain["transformChain"]:
        if transform["m_LocalRotation"] != {"x": 0, "y": 0, "z": 0, "w": 1}:
            raise ValueError("Rotated terrain needs matrix composition")
        if transform["m_LocalScale"] != {"x": 1, "y": 1, "z": 1}:
            raise ValueError("Scaled terrain needs matrix composition")
        for axis, name in enumerate(("x", "y", "z")):
            position[axis] += transform["m_LocalPosition"][name]
    if key in positions:
        raise ValueError("Duplicate scene terrain coordinate")
    positions[key] = position
if set(positions) != set(tiles):
    raise ValueError("Scene transforms do not cover the source heightmaps")
heights = {}
for key, tile in tiles.items():
    data = (root / tile["file"]).read_bytes()
    if hashlib.sha256(data).hexdigest() != tile["fileSHA256"]:
        raise ValueError("Source heightmap checksum differs")
    size = tile["resolution"]
    if size != 257 or len(data) != size * size * 2:
        raise ValueError("Unexpected heightmap resolution")
    heights[key] = struct.unpack("<" + "H" * (size * size), data)
    expected = [-512 + key[0] * 128, 0, -512 + key[1] * 128]
    if positions[key] != expected or tile["scale"] != {"x": .5, "y": 600, "z": .5}:
        raise ValueError("Installed terrain layout/scale changed")
border_mismatches = 0
for (x, z), samples in heights.items():
    if x < 7:
        neighbor = heights[x + 1, z]
        border_mismatches += sum(samples[row * 257 + 256] != neighbor[row * 257] for row in range(257))
    if z < 7:
        neighbor = heights[x, z + 1]
        border_mismatches += sum(samples[256 * 257 + column] != neighbor[column] for column in range(257))

def height_at(x, z):
    column, row = (x + 512) * 2, (z + 512) * 2
    tx, tz = min(7, int(column) // 256), min(7, int(row) // 256)
    lx, lz = column - tx * 256, row - tz * 256
    ix, iz = min(255, int(lx)), min(255, int(lz))
    dx, dz = lx - ix, lz - iz
    samples = heights[tx, tz]
    value = ((1 - dx) * (1 - dz) * samples[iz * 257 + ix]
             + dx * (1 - dz) * samples[iz * 257 + ix + 1]
             + (1 - dx) * dz * samples[(iz + 1) * 257 + ix]
             + dx * dz * samples[(iz + 1) * 257 + ix + 1])
    return value * 600 / 32766

checks = []
for area_id in ("0", "1"):
    center = areas[area_id]["areaCenter"]
    observed = height_at(center["1"], center["3"])
    checks.append({"area": int(area_id), "worldCenter": center,
                   "staticGroundY": center["2"], "heightmapGroundY": observed,
                   "errorMetres": abs(observed - center["2"])})
report = {"terrainTiles": len(tiles), "sceneTransformsVerified": len(positions),
          "worldOrigin": [-512, 0, -512], "worldWidthMetres": 1024,
          "sampleSpacingMetres": .5, "heightScaleMetres": 600,
          "rawHeightDivisor": 32766, "heightDivisorEvidence": "Runtime terrain asset m_HeightMapScale agrees with 600*65535/32766; independent static ground checks",
          "sharedEdgeMismatches": border_mismatches, "areaHeightChecks": checks,
          "renderIntegration": "Not yet enabled", "remaining": ["Global-color texture UV orientation", "Terrain holes semantics", "Vegetation placements and materials"]}
print(json.dumps(report, indent=2))
render_root = json.loads((root / "homeland-render-root-object.json").read_text())
if abs(render_root["m_HeightMapScale"] - 600 * 65535 / 32766) > 0.0001:
    raise ValueError("Original renderer height scale no longer matches normalization")
if border_mismatches or any(item["errorMetres"] > .025 for item in checks):
    sys.exit(1)
