#!/usr/bin/env python3
"""Index UnityFS internal asset filenames using directory metadata only.

Does not decompress mesh/texture payloads. Only unencrypted raw/LZ4 directories
are supported. This resolves cross-bundle CAB references without loading every
game asset. UnityFS layout reference: UnityPy/files/BundleFile.py (MIT).
Usage: index-unity-bundle-directories.py BUNDLE_ROOT OUTPUT_JSON
"""
import io
import json
from pathlib import Path
import struct
import sys
import lz4.block


def take(stream, count):
    data = stream.read(count)
    if len(data) != count:
        raise ValueError("Truncated directory")
    return data


def number(stream, code):
    return struct.unpack(">" + code, take(stream, struct.calcsize(">" + code)))[0]


def string(stream):
    data = bytearray()
    for _ in range(1024):
        value = take(stream, 1)
        if value == b"\0":
            return data.decode("utf-8")
        data.extend(value)
    raise ValueError("Oversized directory string")


def inspect(path):
    with path.open("rb") as stream:
        if string(stream) != "UnityFS":
            raise ValueError("Not UnityFS")
        version = number(stream, "I")
        player, engine = string(stream), string(stream)
        length, compressed, expanded, flags = struct.unpack(">QIII", take(stream, 20))
        if length != path.stat().st_size or not 0 < compressed <= 16 * 1024 * 1024 or not 0 < expanded <= 16 * 1024 * 1024:
            raise ValueError("Invalid bounded directory size")
        if flags & 0x400:
            raise ValueError("Encrypted directory unsupported")
        if version >= 7:
            stream.seek((stream.tell() + 15) // 16 * 16)
        if flags & 0x80:
            stream.seek(length - compressed)
        data = take(stream, compressed)
        compression = flags & 0x3f
        if compression in (2, 3):
            data = lz4.block.decompress(data, uncompressed_size=expanded)
        elif compression != 0:
            raise ValueError("Directory compression unsupported")
        if len(data) != expanded:
            raise ValueError("Directory decompressed length mismatch")
        metadata = io.BytesIO(data)
        take(metadata, 16)
        block_count = number(metadata, "i")
        if not 0 <= block_count <= 1_000_000:
            raise ValueError("Invalid block count")
        take(metadata, block_count * 10)
        count = number(metadata, "i")
        if not 0 <= count <= 100_000:
            raise ValueError("Invalid file count")
        files = []
        for _ in range(count):
            offset, size, file_flags = struct.unpack(">QQI", take(metadata, 20))
            files.append({"name": string(metadata), "offset": offset, "bytes": size, "flags": file_flags})
        return {"bundle": path.name, "bytes": length, "mtimeNS": path.stat().st_mtime_ns,
                "version": version, "engine": engine, "directoryBytesRead": compressed,
                "files": files}


if __name__ == "__main__":
    bundles, errors = [], []
    for path in sorted(Path(sys.argv[1]).glob("*.uab")):
        try:
            bundles.append(inspect(path))
        except (ValueError, OSError, UnicodeError, struct.error) as error:
            errors.append({"bundle": path.name, "error": str(error)})
    report = {"scope": "UnityFS directory metadata only; payloads not decompressed",
              "bundles": bundles, "errors": errors}
    Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + "\n")
    print("Indexed", len(bundles), "bundles; unsupported", len(errors),
          "compressed directory bytes", sum(item["directoryBytesRead"] for item in bundles))
