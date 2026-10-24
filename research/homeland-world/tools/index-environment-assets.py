#!/usr/bin/env python3
"""Resumable path-to-CAB/object index for selected original environment assets."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
patterns = ["asrep_environment_mesh_asset_*.uab", "mexp_environment_exall_0_*.uab",
            "xpt24_mexp_exall_0_*.uab", "xpt24_mexp_exall_1_*.uab", "xpt24_mexp_exall_2_*.uab"]
for path in sorted({path for pattern in patterns for path in root.glob(pattern)}):
    destination = output / (path.stem + ".json")
    stat = path.stat()
    if destination.exists():
        previous = json.loads(destination.read_text())
        if previous.get("bytes") == stat.st_size and previous.get("mtimeNS") == stat.st_mtime_ns:
            print("Cached index", path.name, flush=True)
            continue
    environment = UnityPy.load(str(path))
    entries = []
    for asset_path, pointer in environment.container.items():
        source = pointer.assetsfile
        if pointer.m_FileID:
            cab = source.externals[pointer.m_FileID - 1].path.split("/")[-1]
            type_name = None
        else:
            cab = source.name
            reader = source.objects.get(pointer.m_PathID)
            type_name = reader.type.name if reader is not None else None
        entries.append({"path": asset_path, "cab": cab, "pathID": pointer.m_PathID, "type": type_name})
    if path.stat().st_size != stat.st_size or path.stat().st_mtime_ns != stat.st_mtime_ns:
        raise ValueError("Installed resource changed during indexing")
    report = {"bundle": path.name, "bytes": stat.st_size, "mtimeNS": stat.st_mtime_ns,
              "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "assets": entries}
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print("Indexed assets", path.name, len(entries), flush=True)
