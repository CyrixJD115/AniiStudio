#!/usr/bin/env python3
"""Compare captured block placements with a public layout without uploading data.

Usage: verify-residential-blocks.py CAPTURE CATALOG MANIFEST
Writes a JSON report to stdout. A match proves the observed block arrangement,
not account binding, capture freshness, rendered material fidelity or editability.
"""
import collections
import json
import math
import sys


def verify(capture_path, catalog_path, manifest_path):
    with open(catalog_path) as handle:
        objects = json.load(handle)["catalog"]["objects"]
    prefabs = {
        obj["id"]: obj.get("prefabResourceID", "").strip("$").removesuffix(".prefab")
        for obj in objects
    }
    with open(manifest_path) as handle:
        manifest = json.load(handle)
    expected = {
        name: matrices for name, matrices in manifest["placements"].items()
        if "BuildingBlocks" in name
    }
    with open(capture_path) as handle:
        rows = [json.loads(line) for line in handle if line.strip()]
    actual = collections.defaultdict(list)
    for row in rows:
        prefab = prefabs.get(row.get("homeId"), "")
        if row.get("areaId") == 1 and "BuildingBlocks" in prefab:
            actual[prefab].append(row)
    if not expected or set(actual) != set(expected):
        raise ValueError("Block prefab sets differ or the reference has no blocks")
    keys = [row.get("owningMapKey") for group in actual.values() for row in group]
    if None in keys or len(set(keys)) != len(keys):
        raise ValueError("Missing or duplicate captured instance keys")
    source_points, captured_points = {}, {}
    for prefab in expected:
        if len(expected[prefab]) != len(actual[prefab]):
            raise ValueError(f"Count mismatch: {prefab}")
        source_points[prefab] = [tuple(m[12:15]) for m in expected[prefab]]
        captured_points[prefab] = [
            (row["position"][2] / 100, row["position"][1] / 100, row["position"][0] / 100)
            for row in actual[prefab]
        ]
    source_all = [p for points in source_points.values() for p in points]
    captured_all = [p for points in captured_points.values() for p in points]
    if not all(math.isfinite(v) for p in source_all + captured_all for v in p):
        raise ValueError("Nonfinite position")
    count = len(keys)
    delta = [sum(p[axis] for p in captured_all) / count
             - sum(p[axis] for p in source_all) / count for axis in range(3)]
    # Sorting preserves color identity. This compares positions only; no best-fit
    # rotation or deformation can conceal a mirrored or rearranged construction.
    maximum_error = 0.0
    for prefab in expected:
        translated = sorted(tuple(p[a] + delta[a] for a in range(3)) for p in source_points[prefab])
        for source, captured in zip(translated, sorted(captured_points[prefab])):
            maximum_error = max(maximum_error, math.dist(source, captured))
    report = {
        "capture": capture_path, "catalog": catalog_path, "reference": manifest_path,
        "referenceLayout": manifest.get("n"), "area": 1,
        "pieceCount": count, "prefabCount": len(expected),
        "countsByPrefab": {p: len(actual[p]) for p in sorted(actual)},
        "sourceToCapturedTranslation": delta,
        "maximumPositionErrorMetres": maximum_error,
        "positionToleranceMetres": 0.01,
        "allPositionsMatch": maximum_error <= 0.01,
        "rawRotations": sorted({tuple(row["rotation"]) for group in actual.values() for row in group}),
        "rawScales": sorted({tuple(row["scale"]) for group in actual.values() for row in group}),
        "limits": "Positions and counts only; rendered materials, model orientation, account binding and freshness require separate verification."
    }
    return report


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    result = verify(*sys.argv[1:])
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["allPositionsMatch"] else 1)
