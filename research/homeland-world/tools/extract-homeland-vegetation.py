#!/usr/bin/env python3
"""Preserve static vegetation serialization and its Unity reference table."""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
bundle = next(root.glob("mexp_level_exall_0_*.uab"))
env = UnityPy.load(str(bundle))
key = next(key for key in env.container if "Home_01_ExportVegetationStorage" in key)
reader = env.container[key].deref()
tree = reader.read_typetree()
serialization = tree["serializationData"]
if serialization["SerializedFormat"] != 0 or len(serialization["SerializedBytes"]) > 16 * 1024 * 1024:
    raise ValueError("Unsupported vegetation serialization format or size")
data = bytes(serialization["SerializedBytes"])
(output / "vegetation-odin.bin").write_bytes(data)
report = {"sourceBundle": bundle.name, "sourceAsset": key,
          "sourceSHA256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
          "dataSHA256": hashlib.sha256(data).hexdigest(),
          "prototypeOrder": tree["m_ProtoOrder"], "visibilityGroups": tree["m_VisibilityGroupStorage"],
          "unityReferences": serialization["ReferencedUnityObjects"],
          "externalFiles": [item.path for item in reader.assets_file.externals]}
(output / "vegetation-references.json").write_text(json.dumps(report, indent=2) + "\n")
print("Preserved vegetation bytes", len(data), "Unity references", len(report["unityReferences"]), flush=True)
