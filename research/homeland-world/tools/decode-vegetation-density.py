#!/usr/bin/env python3
"""Read original density-map channels; do not synthesize procedural placements.

GeneratePointCloud's DensityMapMask selects sequential channels by bits1/2/4/8.
Only the observed masks1/5, original Unity R16/RG32 formats are accepted here.
DensityInv and other CPU-side dispatch constants remain separate research.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

spec = importlib.util.spec_from_file_location("vegetation_sections", Path(__file__).with_name("inspect-vegetation-chunks.py"))
sections = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sections)


def decode(data):
    info = sections.decode(data)
    grid = info["grid"]
    mask = grid["formatTag"]
    if mask == 0:
        return None
    if mask not in (1, 5):
        raise ValueError("Unverified density channel mask")
    texture_format = grid["opaqueFlags"] & 255
    channels = 1 if mask == 1 else 2
    if texture_format != (9 if channels == 1 else 72):
        raise ValueError("Expected original Unity R16/RG32 source texture format")
    size = grid["width"] * grid["height"] * channels * 2
    payload = grid["payload"]
    if payload["byteLength"] != size:
        raise ValueError("Density texture dimensions/format disagree with payload length")
    raw = data[payload["offset"]:payload["offset"]+size]
    words = struct.unpack("<" + "H" * (size // 2), raw)
    density = words[::channels]
    scale = words[1::channels] if channels == 2 else None
    return {"width": grid["width"], "height": grid["height"], "mask": mask,
            "textureFormat": "R16" if channels == 1 else "RG32",
            "densityU16": density, "scaleU16": scale,
            "sourcePayloadSHA256": hashlib.sha256(raw).hexdigest()}


if __name__ == "__main__":
    root, output = map(Path, sys.argv[1:3])
    output.mkdir(parents=True, exist_ok=True)
    reports = []
    for path in sorted(root.glob("*.pack")):
        source = path.read_bytes()
        for record in sections.stream.decode(source):
            grid = decode(record["bytes"])
            if grid is None:
                continue
            report = {k: v for k,v in grid.items() if k not in ("densityU16", "scaleU16")}
            report.update(chunk=path.name, prototypeID=record["id"], sourceSHA256=hashlib.sha256(source).hexdigest())
            for key in ("densityU16", "scaleU16"):
                values = grid[key]
                if values is None:
                    continue
                filename = f'{path.stem}-id{record["id"]}-{key}.u16le'
                raw = struct.pack("<" + "H"*len(values), *values)
                (output / filename).write_bytes(raw)
                report[key] = {"file": filename, "sha256": hashlib.sha256(raw).hexdigest(),
                               "min": min(values), "max": max(values),
                               "nonzeroSamples": sum(v > 0 for v in values)}
            reports.append(report)
    (output / "manifest.json").write_text(json.dumps({"maps": reports,
        "semantics": "Density normalized U16; scale channel normalized U16 times2 per original shader. No procedural positions generated; CPU constants not yet verified."}, indent=2) + "\n")
    print("Decoded", len(reports), "original density maps; occupied texels",
          sum(r["densityU16"]["nonzeroSamples"] for r in reports))
