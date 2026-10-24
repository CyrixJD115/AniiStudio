#!/usr/bin/env python3
"""Preserve the exact original pattern asset linked by the Home vegetation system."""
import hashlib
import json
import math
from pathlib import Path
import sys
import UnityPy

root, output = map(Path, sys.argv[1:3])
source = root / "pk_xrender_asset_0_77f2d8a4a3dfc55958fc9811627c84a7.uab"
environment = UnityPy.load(str(source))
obj = next(o for o in environment.objects if o.path_id == 6675825702353143427)
data = obj.read_typetree()
patterns = data["m_Patterns"]
if len(patterns) != 64 or any(len(p["m_Points"]) != 64 for p in patterns):
    raise ValueError("Original pattern dimensions changed")
if any(not math.isfinite(v) or not 0 <= v <= 1 for p in patterns for xy in p["m_Points"] for v in xy.values()):
    raise ValueError("Invalid original pattern point")
report = {"sourceBundle": source.name, "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
          "sourceCAB": obj.assets_file.name, "pathID": obj.path_id, "type": obj.type.name,
          "externalFiles": [x.path for x in obj.assets_file.externals], "data": data}
output.write_text(json.dumps(report, indent=2) + "\n")
print("Preserved64 original patterns /4096 original points; not world placements")
