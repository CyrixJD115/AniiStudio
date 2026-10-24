#!/usr/bin/env python3
"""Validate observed static vegetation chunk sections, preserving opaque GPU data.

The 16-byte instance records are NOT decoded transforms. Bounds are metadata,
not individual positions. This inspector deliberately does not invent placement.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


storage = load("vegetation_storage", "read-vegetation-storage.py")
stream = load("xrender_stream", "read-xrender-stream.py")


def section(reader):
    size = reader.count(8 * 1024 * 1024)
    offset = reader.pos
    data = reader.take(size)
    return {"offset": offset, "byteLength": size,
            "sha256": hashlib.sha256(data).hexdigest()}


def bounds(reader):
    return {"center": reader.floats(3), "extents": reader.floats(3),
            "opaqueRange": reader.floats(2)}


def decode(data):
    r = storage.Reader(data)
    texture = {"formatTag": r.number("I")}
    if texture["formatTag"]:
        texture.update(width=r.number("H"), height=r.number("H"),
                       opaqueFlags=r.number("H"), opaqueTextureOption=r.number("B"))
        if not 0 < texture["width"] <= 4096 or not 0 < texture["height"] <= 4096:
            raise ValueError("Invalid grid dimensions")
        texture["payload"] = section(r)
    texture["bounds"] = bounds(r)
    instances = section(r)
    indices = section(r)
    if instances["byteLength"] % 16 or indices["byteLength"] != instances["byteLength"] // 4:
        raise ValueError("Instance/index record lengths disagree")
    count = instances["byteLength"] // 16
    result = {"grid": texture, "opaqueInstances": instances, "instanceIndices": indices,
              "packedInstanceCount": count, "instanceBounds": bounds(r)}
    if r.pos != len(data):
        raise ValueError("Unparsed chunk tail")
    return result


if __name__ == "__main__":
    root, definitions, output = map(Path, sys.argv[1:4])
    definitions = json.loads(definitions.read_text())
    by_id = {p["id"]: p for p in definitions["prototypes"]}
    results = []
    for path in sorted(root.glob("*.pack")):
        data = path.read_bytes()
        records = []
        for entry in stream.decode(data):
            identity = entry["id"]
            records.append({"id": identity, "prefab": by_id.get(identity, {}).get("name"),
                            "prototypeResolved": identity in by_id,
                            **decode(entry["bytes"])})
        results.append({"file": path.name, "sha256": hashlib.sha256(data).hexdigest(),
                        "records": records})
    output.write_text(json.dumps({"chunks": results}, indent=2) + "\n")
    print("Chunks:", len(results), "records:", sum(len(c["records"]) for c in results),
          "opaque packed instances:", sum(r["packedInstanceCount"] for c in results for r in c["records"]))
