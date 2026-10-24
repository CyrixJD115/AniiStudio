#!/usr/bin/env python3
"""Preserve original material DXBC and parsed shader metadata for offline inspection."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import UnityPy
import zstandard
from UnityPy.export.ShaderConverter import ShaderSubProgram
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader

def gpu_references(parsed):
    """Parameter blob indices are separate data, never executable shader entries."""
    names=parsed["m_KeywordNames"];result={}
    for subshader_index,subshader in enumerate(parsed["m_SubShaders"]):
        for pass_index,shader_pass in enumerate(subshader["m_Passes"]):
            for stage,data in shader_pass.items():
                if not stage.startswith("prog") or not isinstance(data,dict):continue
                for group in data.get("m_PlayerSubPrograms",[]):
                    for reference in group:
                        indices=reference["m_KeywordIndices"]
                        if any(i<0 or i>=len(names) for i in indices):raise ValueError("Invalid shader keyword index")
                        key=(reference["m_ShaderCompilerPlatform"],reference["m_BlobIndex"])
                        result.setdefault(key,[]).append({"subshader":subshader_index,"pass":pass_index,
                            "stage":stage,"keywords":[names[i] for i in indices]})
    return result


def gpu_entry(segments,index):
    raw=segments[0]
    if len(raw)<4:raise ValueError("Missing program table")
    count=struct.unpack_from("<I",raw)[0]
    if count>250000 or 4+12*count>len(raw) or not 0<=index<count:raise ValueError("Invalid program table index")
    offset,size,segment=struct.unpack_from("<III",raw,4+12*index)
    if segment>=len(segments) or not 0<size<=32*1024*1024 or offset+size>len(segments[segment]) or (segment==0 and offset<4+12*count):
        raise ValueError("Program entry exceeds source segment")
    return segment,segments[segment][offset:offset+size]


def dxbc_container(code):
    begin=code.find(b"DXBC")
    if begin<0:return None
    # Unity's GPU wrapper can include input-binding metadata before the container
    # (66 bytes in a verified rock vertex program). The exact GPU entry already
    # bounds the search; do not impose an invented fixed-size prefix limit.
    if begin+32>len(code):raise ValueError("Truncated DXBC header in GPU entry")
    size,chunks=struct.unpack_from("<II",code,begin+24)
    if size<32 or begin+size>len(code) or chunks>1024 or 32+4*chunks>size:
        raise ValueError("Invalid bounded DXBC container")
    data=code[begin:begin+size]
    for offset in struct.unpack_from("<"+"I"*chunks,data,32):
        if offset<32+4*chunks or offset+8>size:raise ValueError("Invalid DXBC chunk offset")
        length=struct.unpack_from("<I",data,offset+4)[0]
        if offset+8+length>size:raise ValueError("DXBC chunk exceeds program")
    return data


def main():
    root,index_path,material_path,output=map(Path,sys.argv[1:5])
    material=json.loads(material_path.read_text());pointer=material["data"]["m_Shader"]
    cab=material["externalFiles"][pointer["m_FileID"]-1].split("/")[-1] if pointer["m_FileID"] else material["sourceCAB"]
    index=json.loads(index_path.read_text())
    source=root/next(b["bundle"] for b in index["bundles"] if any(f["name"].lower()==cab.lower() for f in b["files"]))
    environment=UnityPy.load(str(source))
    obj=next(o for o in environment.objects if o.path_id==pointer["m_PathID"] and o.assets_file.name.lower()==cab.lower())
    if obj.version<(2019,3):raise ValueError("Older program table layout unsupported")
    shader=obj.read();parsed=obj.read_typetree()["m_ParsedForm"];references=gpu_references(parsed)
    output.mkdir(parents=True,exist_ok=True);rows=[];skipped=[]
    for platform,offsets,lengths,raw_lengths in zip(shader.platforms,shader.offsets,shader.compressedLengths,shader.decompressedLengths):
        offsets=offsets if isinstance(offsets,list) else [offsets]
        lengths=lengths if isinstance(lengths,list) else [lengths]
        raw_lengths=raw_lengths if isinstance(raw_lengths,list) else [raw_lengths]
        segments=[]
        for offset,length,raw_length in zip(offsets,lengths,raw_lengths):
            if raw_length>32*1024*1024:raise ValueError("Shader segment exceeds inspection bound")
            compressed=bytes(shader.compressedBlob)[offset:offset+length]
            if compressed[:4]==bytes.fromhex("28b52ffd"):
                if zstandard.frame_content_size(compressed)!=raw_length:raise ValueError("Shader frame/envelope mismatch")
                raw=zstandard.ZstdDecompressor().decompress(compressed,max_output_size=raw_length,allow_extra_data=False)
            else:raw=CompressionHelper.decompress_lz4(compressed,raw_length)
            segments.append(raw)
        for (target,i),variants in sorted(references.items()):
            if target!=platform:continue
            segment,entry=gpu_entry(segments,i)
            program=ShaderSubProgram(EndianBinaryReader(entry,endian="<"))
            try:dxbc=dxbc_container(bytes(program.m_ProgramCode))
            except ValueError as error:
                raise ValueError(f"GPU blob {platform}/{i}, entryBytes={len(entry)}, codeBytes={len(program.m_ProgramCode)}, marker={bytes(program.m_ProgramCode).find(b'DXBC')}, type={program.m_ProgramType}: {error}") from error
            if dxbc is None:skipped.append({"platform":platform,"blobIndex":i});continue
            filename=f"program-p{platform}-s{segment}-v{i}.dxbc";(output/filename).write_bytes(dxbc)
            rows.append({"file":filename,"platform":platform,"blobIndex":i,"type":program.m_ProgramType.name,
                         "variants":variants,"sha256":hashlib.sha256(dxbc).hexdigest(),"bytes":len(dxbc)})
    (output/"parsed-shader.json").write_text(json.dumps(parsed,indent=2)+"\n")
    report={"sourceBundle":source.name,"sourceSHA256":hashlib.sha256(source.read_bytes()).hexdigest(),
            "sourceCAB":cab,"pathID":obj.path_id,"shaderName":shader.m_ParsedForm.m_Name,
            "programs":rows,"nonDXBCSkipped":skipped,
            "selection":"Only explicit m_PlayerSubPrograms GPU indices; parameter blob entries excluded. Keywords from parsed index table."}
    (output/"manifest.json").write_text(json.dumps(report,indent=2)+"\n")
    print(report["shaderName"],"referenced GPU programs",len(rows),"nonDXBC skipped",len(skipped))


if __name__=="__main__":main()
