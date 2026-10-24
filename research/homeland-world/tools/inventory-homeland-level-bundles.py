#!/usr/bin/env python3
"""Bounded, read-only inventory of selected level bundles for scenery research."""
import collections
import json
from pathlib import Path
import sys
import UnityPy

root, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
patterns = ["mexp_level_*.uab", "mres_level_*.uab", "ares_level_levelstream_*.uab",
            "ares_common_level_*.uab"]
for path in sorted({p for pattern in patterns for p in root.glob(pattern)}):
    target = output / (path.stem + ".json")
    if target.exists():
        print("Already inventoried", path.name, flush=True)
        continue
    environment = UnityPy.load(str(path))
    containers = list(environment.container)
    home = [key for key in containers if "home" in key.lower()]
    names = []
    for obj in environment.objects:
        if obj.type.name in ("MonoBehaviour", "TextAsset"):
            name = obj.peek_name()
            if "home" in name.lower():
                names.append({"type": obj.type.name, "name": name, "pathID": obj.path_id})
    report = {"bundle": path.name, "bytes": path.stat().st_size,
              "types": dict(collections.Counter(obj.type.name for obj in environment.objects)),
              "homeContainers": home, "homeNamedObjects": names,
              "containerSample": containers[:8]}
    target.write_text(json.dumps(report, indent=2))
    print(path.name, "home containers", len(home), "named objects", len(names), flush=True)
