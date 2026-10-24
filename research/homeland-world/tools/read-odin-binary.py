#!/usr/bin/env python3
"""Bounded offline inspection of Odin binary entries; never instantiates types.

Format reference: TeamSirenix/odin-serializer BinaryEntryType and BinaryDataReader
at https://github.com/TeamSirenix/odin-serializer (Apache-2.0).
This independent structural reader preserves references and raw primitive bytes;
it does not execute serialization callbacks or interpret unknown engine classes.
Usage: read-odin-binary.py INPUT OUTPUT_JSON
"""
import json
import math
from pathlib import Path
import struct
import sys


class Reader:
    def __init__(self, data):
        if len(data) > 16 * 1024 * 1024:
            raise ValueError("Input exceeds inspection bound")
        self.data, self.pos, self.types, self.entries = data, 0, {}, 0

    def take(self, count):
        if count < 0 or self.pos + count > len(self.data):
            raise ValueError(f"Truncated entry at {self.pos}")
        result = self.data[self.pos:self.pos + count]
        self.pos += count
        return result

    def number(self, code):
        value = struct.unpack("<" + code, self.take(struct.calcsize("<" + code)))[0]
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("Nonfinite serialized number")
        return value

    def string(self):
        width = self.number("B")
        count = self.number("i")
        if width not in (0, 1) or not 0 <= count <= 1_000_000:
            raise ValueError("Invalid string header")
        return self.take(count * (1 + width)).decode("utf-16-le" if width else "latin-1")

    def type_name(self):
        kind = self.number("B")
        if kind == 46:
            return None
        if kind == 47:
            identity, name = self.number("i"), self.string()
            if identity in self.types:
                raise ValueError("Duplicate type definition")
            self.types[identity] = name
            return name
        if kind == 48:
            identity = self.number("i")
            if identity not in self.types:
                raise ValueError("Unknown type reference")
            return self.types[identity]
        raise ValueError(f"Invalid type metadata {kind} at {self.pos}")

    def sequence(self, depth=0, stop=None):
        if depth > 64:
            raise ValueError("Nesting exceeds inspection bound")
        values = []
        while self.pos < len(self.data):
            offset = self.pos
            kind = self.number("B")
            if kind == stop:
                return values
            if kind == 49 and stop is None and self.pos == len(self.data):
                return values
            self.entries += 1
            if self.entries > 1_000_000:
                raise ValueError("Too many entries")
            named = kind in (1, 3, 9, 11, 13, 50) or 15 <= kind <= 45 and kind % 2 == 1
            entry = {"offset": offset, "kind": kind}
            if named:
                entry["name"] = self.string()
            if kind in (1, 2, 3, 4):
                entry["type"] = self.type_name()
                if kind in (1, 2):
                    entry["id"] = self.number("i")
                entry["children"] = self.sequence(depth + 1, 5)
            elif kind == 6:
                count = self.number("q")
                if not 0 <= count <= 1_000_000:
                    raise ValueError("Invalid array length")
                entry["length"] = count
                entry["children"] = self.sequence(depth + 1, 7)
                if len(entry["children"]) != count:
                    raise ValueError("Array element count mismatch")
            elif kind == 8:
                count, width = self.number("i"), self.number("i")
                if not 0 <= count <= 1_000_000 or width not in (1, 2, 4, 8, 16):
                    raise ValueError("Invalid primitive array dimensions")
                entry.update(length=count, elementBytes=width, dataOffset=self.pos)
                entry["dataHex"] = self.take(count * width).hex()
            elif kind in (9, 10):
                entry["internalReference"] = self.number("i")
            elif kind in (11, 12):
                entry["externalReference"] = self.number("i")
            elif kind in (13, 14, 41, 42):
                entry["guidBytes"] = self.take(16).hex()
            elif 15 <= kind <= 34:
                codes = {15: "b", 17: "B", 19: "h", 21: "H", 23: "i", 25: "I",
                         27: "q", 29: "Q", 31: "f", 33: "d"}
                entry["value"] = self.number(codes[kind if kind % 2 else kind - 1])
            elif kind in (35, 36):
                entry["decimalBytes"] = self.take(16).hex()
            elif kind in (37, 38):
                entry["value"] = self.take(2).decode("utf-16-le")
            elif kind in (39, 40, 50, 51):
                entry["value"] = self.string()
            elif kind in (43, 44):
                value = self.number("B")
                if value not in (0, 1):
                    raise ValueError("Invalid boolean")
                entry["value"] = bool(value)
            elif kind in (45, 46):
                entry["value"] = None
            else:
                raise ValueError(f"Unsupported entry {kind} at {offset}")
            values.append(entry)
        if stop is not None:
            raise ValueError("Unclosed container")
        return values


if __name__ == "__main__":
    reader = Reader(Path(sys.argv[1]).read_bytes())
    result = reader.sequence()
    Path(sys.argv[2]).write_text(json.dumps({"bytesConsumed": reader.pos,
        "entryCount": reader.entries, "types": reader.types, "entries": result}, indent=2) + "\n")
    print("Decoded", reader.entries, "structural entries; consumed", reader.pos, "bytes")
