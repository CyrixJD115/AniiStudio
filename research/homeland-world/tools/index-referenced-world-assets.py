#!/usr/bin/env python3
"""Index missing static-world resources by actual Unity reference/CAB dependencies.

Does not guess current patch prefixes or decompress every installed game bundle.
Existing indexes are reused only when source byte length/mtime still agree.
"""
import hashlib
import json
from pathlib import Path
import sys
import UnityPy

root, cab_path, references_path, output = map(Path,sys.argv[1:5])
output.mkdir(parents=True,exist_ok=True)
index=json.loads(cab_path.read_text())
lookup={f["name"].lower():b["bundle"] for b in index["bundles"] for f in b["files"]}
known=set()
for path in output.glob("*.json"):
    previous=json.loads(path.read_text())
    source=root/previous["bundle"]
    if not source.exists():continue
    stat=source.stat()
    if stat.st_size!=previous["bytes"] or stat.st_mtime_ns!=previous["mtimeNS"]:continue
    known.update((a["cab"].lower(),a["pathID"]) for a in previous["assets"])
references=json.loads(references_path.read_text())
bundles=set()
for table in references.values():
    # XBatch uses singular; XChunk uses plural. Both are explicit Unity PPtrs.
    pointers = table["data"].get("m_Reference",[]) + table["data"].get("m_References",[])
    for pointer in pointers:
        if not pointer["m_PathID"]:continue
        if not 1 <= pointer["m_FileID"] <= len(table["externalFiles"]):
            raise ValueError("Unsupported local reference scope")
        cab=table["externalFiles"][pointer["m_FileID"]-1].split("/")[-1]
        if (cab.lower(),pointer["m_PathID"]) not in known:
            if cab.lower() not in lookup:raise ValueError("Refresh CAB directory index: missing referenced file")
            bundles.add(lookup[cab.lower()])
for name in sorted(bundles):
    path=root/name;stat=path.stat()
    environment=UnityPy.load(str(path));assets=[]
    for asset_path,pointer in environment.container.items():
        source=pointer.assetsfile
        if pointer.m_FileID:
            cab=source.externals[pointer.m_FileID-1].path.split("/")[-1];kind=None
        else:
            cab=source.name;obj=source.objects.get(pointer.m_PathID);kind=obj.type.name if obj else None
        assets.append({"path":asset_path,"cab":cab,"pathID":pointer.m_PathID,"type":kind})
    if path.stat().st_size!=stat.st_size or path.stat().st_mtime_ns!=stat.st_mtime_ns:
        raise ValueError("Referenced resource changed during indexing")
    report={"bundle":name,"bytes":stat.st_size,"mtimeNS":stat.st_mtime_ns,
            "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"assets":assets,
            "discovery":"Explicit static-world Unity references via CAB index, no patch-name assumptions"}
    (output/(path.stem+".json")).write_text(json.dumps(report,indent=2)+"\n")
    print("Indexed referenced bundle",name,len(assets),flush=True)
print("New/refreshed referenced bundles",len(bundles))
