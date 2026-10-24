#!/usr/bin/env python3
"""Bounded structural decoder for observed Aniimo XRender Zstandard wrappers.

Usage: read-xrender-stream.py INPUT_FILE OUTPUT_DIRECTORY
Preserves unknown format tags and record IDs; it does not guess transforms or
instantiate game objects. Supports observed FF/bin and FF00/pack directories.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zstandard

LIMIT = 64 * 1024 * 1024


def block(data, limit=LIMIT):
    if len(data) < 9:
        raise ValueError("Truncated compressed block")
    tag = data[0]
    packed, raw = struct.unpack_from("<II", data, 1)
    if tag not in (0, 1, 2, 3, 7) or packed != len(data) - 9 or not 0 < raw <= limit:
        raise ValueError("Unsupported tag or invalid bounded block length")
    payload = data[9:]
    if not payload.startswith(b"\x28\xb5\x2f\xfd"):
        raise ValueError("Expected Zstandard frame")
    # max_output_size alone does not constrain allocation when the frame
    # advertises its own content size. Validate that size before decompression.
    if zstandard.get_frame_parameters(payload).content_size != raw:
        raise ValueError("Frame content size differs from bounded envelope")
    result = zstandard.ZstdDecompressor().decompress(payload, max_output_size=raw, allow_extra_data=False)
    if len(result) != raw:
        raise ValueError("Decompressed length differs from declaration")
    return tag, result


def decode(data):
    if not 2 <= len(data) <= LIMIT or data[0] != 255:
        raise ValueError("Invalid or oversized stream envelope")
    if data[1] in (1, 2, 3):
        tag, result = block(data[1:])
        return [{"id": None, "formatTag": tag, "bytes": result}]
    if data[1] != 0 or len(data) < 6:
        raise ValueError("Unsupported stream envelope")
    directory_bytes = struct.unpack_from("<I", data, 2)[0]
    if directory_bytes % 12 or directory_bytes > len(data) - 6 or directory_bytes > 100_000 * 12:
        raise ValueError("Invalid bounded directory length")
    entries = [struct.unpack_from("<III", data, 6 + offset) for offset in range(0, directory_bytes, 12)]
    if len({entry[0] for entry in entries}) != len(entries):
        raise ValueError("Duplicate directory record IDs")
    expected = 6 + directory_bytes
    for identity, offset, length in sorted(entries, key=lambda entry: entry[1]):
        if offset != expected or length < 9 or offset + length > len(data):
            raise ValueError("Overlapping, missing or out-of-bounds record data")
        expected = offset + length
    if expected != len(data):
        raise ValueError("Trailing or unreferenced payload bytes")
    results, total = [], 0
    for identity, offset, length in entries:
        tag, result = block(data[offset:offset + length], LIMIT - total)
        total += len(result)
        if total > LIMIT:
            raise ValueError("Aggregate decompression exceeds inspection bound")
        results.append({"id": identity, "formatTag": tag, "bytes": result})
    return results


if __name__ == "__main__":
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    if source.stat().st_size > LIMIT:
        raise ValueError("Source file exceeds inspection bound")
    data = source.read_bytes()
    records = decode(data)
    output.mkdir(parents=True, exist_ok=True)
    report = {"source": str(source), "sourceSHA256": hashlib.sha256(data).hexdigest(),
              "scope": "Validated wrapper only; inner record schema not yet interpreted", "records": []}
    for record in records:
        filename = f"record-{record['id'] if record['id'] is not None else 'root'}.bin"
        (output / filename).write_bytes(record["bytes"])
        report["records"].append({"id": record["id"], "formatTag": record["formatTag"],
            "file": filename, "bytes": len(record["bytes"]),
            "sha256": hashlib.sha256(record["bytes"]).hexdigest()})
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Validated", len(records), "records; decompressed bytes", sum(len(record["bytes"]) for record in records))
