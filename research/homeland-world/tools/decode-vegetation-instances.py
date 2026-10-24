#!/usr/bin/env python3
"""Decode static scenery transforms from the original compressed-bounds shader.

Formula evidence: GenerateBlockAABB/GenerateLeafAABBCompress DXBC disassembly,
saved alongside the source/hash manifest. Never reads/writes player or server data.
"""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import sys

spec = importlib.util.spec_from_file_location("vegetation_sections", Path(__file__).with_name("inspect-vegetation-chunks.py"))
sections = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sections)


def decode(data):
    if len(data) != 16:
        raise ValueError("Compressed transform must be 16 bytes")
    a, b, c, d = struct.unpack("<4I", data)
    position = [(a & 0xfffff) / 128 - 4096,
                ((((c >> 16) & 63) << 12) + (b >> 20)) / 128 - 1024,
                (b & 0xfffff) / 128 - 4096]
    scale = (a >> 20) * 0.000976801035
    packed = [c & 65535, d & 65535, d >> 16]
    missing = ((packed[1] >> 15) << 1) + (packed[2] >> 15)
    values = [(p & 16383) * 0.000043161006 * (1 if p & 16384 else -1) for p in packed]
    length = sum(v*v for v in values)
    if length > 1.00001:
        raise ValueError("Invalid compressed quaternion")
    values.insert(missing, math.sqrt(max(0, 1-length)) * (1 if packed[0] >> 15 else -1))
    return {"position": position, "rotationXYZW": values, "uniformScale": scale}


def transformed_bounds(instance, bounds):
    x, y, z, w = instance["rotationXYZW"]
    r = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    s = instance["uniformScale"]
    center = [instance["position"][i] + s*sum(r[i][j]*bounds["center"][j] for j in range(3)) for i in range(3)]
    extents = [s*sum(abs(r[i][j])*bounds["extents"][j] for j in range(3)) for i in range(3)]
    return center, extents


if __name__ == "__main__":
    root, definition_path, output = map(Path, sys.argv[1:4])
    definitions = json.loads(definition_path.read_text())
    by_id = {p["id"]: p for p in definitions["prototypes"]}
    rows, validations, unresolved = [], [], set()
    for path in sorted(root.glob("*.pack")):
        source = path.read_bytes()
        for record in sections.stream.decode(source):
            info = sections.decode(record["bytes"])
            start = info["opaqueInstances"]["offset"]
            index_start = info["instanceIndices"]["offset"]
            instances = []
            for i in range(info["packedInstanceCount"]):
                raw = record["bytes"][start+16*i:start+16*(i+1)]
                instance = {"ordinal": i, "sourceIndex": struct.unpack_from("<I", record["bytes"], index_start+4*i)[0],
                            "packedHex": raw.hex(), **decode(raw)}
                instances.append(instance)
            prototype = by_id.get(record["id"])
            rows.append({"chunk": path.name, "sourceSHA256": hashlib.sha256(source).hexdigest(),
                         "prototypeID": record["id"], "prefab": prototype["name"] if prototype else None,
                         "instances": instances})
            if instances and prototype:
                transformed = [transformed_bounds(v, prototype["bounds"]) for v in instances]
                low = [min(c[a]-e[a] for c,e in transformed) for a in range(3)]
                high = [max(c[a]+e[a] for c,e in transformed) for a in range(3)]
                expected = info["instanceBounds"]
                errors = [abs((low[a]+high[a])/2-expected["center"][a]) for a in range(3)]
                errors += [abs((high[a]-low[a])/2-expected["extents"][a]) for a in range(3)]
                validations.append({"chunk": path.name, "prototypeID": record["id"],
                                    "instances": len(instances), "maxBoundsErrorMetres": max(errors)})
            elif instances:
                unresolved.add(record["id"])
    report = {"schema": "original-compressed-vegetation-v1", "chunks": rows,
              "boundsCrosschecks": validations, "unresolvedPrefabIDsWithInstances": sorted(unresolved)}
    output.write_text(json.dumps(report, indent=2) + "\n")
    errors = sorted(v["maxBoundsErrorMetres"] for v in validations)
    print("Decoded", sum(len(r["instances"]) for r in rows), "transforms; bounds checks", len(errors),
          "median/max errors", errors[len(errors)//2], max(errors))
