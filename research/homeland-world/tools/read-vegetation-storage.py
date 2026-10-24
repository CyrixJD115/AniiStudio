#!/usr/bin/env python3
"""Bounded offline reader for the observed Homeland vegetation definition stream.

This reads static scenery definitions, never player saves or executable objects.
Unknown bytes remain explicitly opaque; shader and placement semantics are separate.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys


class Reader:
    def __init__(self, data):
        if len(data) > 16 * 1024 * 1024:
            raise ValueError("Storage exceeds bound")
        self.data, self.pos = data, 0

    def take(self, count):
        if count < 0 or self.pos + count > len(self.data):
            raise ValueError(f"Truncated storage at {self.pos}")
        result = self.data[self.pos:self.pos + count]
        self.pos += count
        return result

    def number(self, code):
        value = struct.unpack("<" + code, self.take(struct.calcsize("<" + code)))[0]
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("Nonfinite value")
        return value

    def count(self, limit=4096):
        value = self.number("I")
        if value > limit:
            raise ValueError(f"Count {value} exceeds {limit} at {self.pos - 4}")
        return value

    def boolean(self):
        value = self.number("B")
        if value not in (0, 1):
            raise ValueError(f"Invalid Boolean at {self.pos - 1}")
        return bool(value)

    def string(self):
        length = 0
        for shift in range(0, 35, 7):
            byte = self.number("B")
            length |= (byte & 127) << shift
            if not byte & 128:
                if length > 16384:
                    raise ValueError("String exceeds bound")
                return self.take(length).decode("utf-8")
        raise ValueError("Invalid 7-bit string length")

    def floats(self, count):
        return [self.number("f") for _ in range(count)]

    def prototype(self):
        start = self.pos
        result = {"offset": start, "id": self.number("I"), "name": self.string()}
        result["meshLODs"] = [[self.string() for _ in range(self.count(32))]
                              for _ in range(self.count(8))]
        result["materialLODs"] = [[[self.string() for _ in range(self.count(32))]
                                   for _ in range(self.count(32))]
                                  for _ in range(self.count(8))]
        result["shadowLODs"] = [[self.number("i") for _ in range(self.count(32))]
                                for _ in range(self.count(8))]
        result["lodDistances"] = self.floats(self.count(8))
        result["cullDistance"] = self.number("f")
        result["bounds"] = {"center": self.floats(3), "extents": self.floats(3)}
        result["localToWorld"] = self.floats(16)
        result["position"] = self.floats(3)
        result["rotation"] = self.floats(4)
        result["lossyScaleY"] = self.number("f")
        result["settingsOffset"] = self.pos
        result["vegetationType"] = self.number("i")
        result["opaqueBeforeFlags"] = self.number("B")
        result["castShadow"] = self.boolean()
        result["enableCollision"] = self.boolean()
        result["overrideDensityCurve"] = self.boolean()
        result["curvePrefix"] = self.number("I")
        result["curveKeys"] = []
        for _ in range(self.count(64)):
            key = dict(zip(("time", "value", "inTangent", "outTangent"), self.floats(4)))
            key.update(tangentMode=self.number("i"), weightedMode=self.number("i"))
            key.update(zip(("inWeight", "outWeight"), self.floats(2)))
            result["curveKeys"].append(key)
        result["curveWrapModes"] = [self.number("i"), self.number("i")]
        result["opaqueAfterCurve"] = self.number("B")
        for name, kind in (("enableCustomCullDistance", "bool"), ("customCullDistance", "f"),
                           ("influenceGrassTex", "bool"), ("grassTexHeightScale", "f"),
                           ("useLodCull", "bool"), ("lodFactor", "f"),
                           ("enableCrossFade", "bool"), ("collisionBoundingScale", "f"),
                           ("dyeingLayer", "i"), ("customTag", "string"), ("pcOnly", "bool"),
                           ("batchGroup", "i"), ("isBatchGroupLeader", "bool"), ("density", "f"),
                           ("useNormalDirection", "bool"), ("overrideSlopeLimit", "bool"),
                           ("slopeLimit", "f"), ("enableRandomRotation", "bool"),
                           ("rotateMin", "f"), ("rotateMax", "f"), ("enableRandomScale", "bool"),
                           ("scaleMin", "f"), ("scaleMax", "f")):
            result[name] = (self.boolean() if kind == "bool" else
                            self.string() if kind == "string" else self.number(kind))
        result["byteLength"] = self.pos - start
        return result


def decode(data):
    reader = Reader(data)
    prototypes = [reader.prototype() for _ in range(reader.count(1024))]
    ids = [p["id"] for p in prototypes]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate prototype ID")
    return {"sourceSHA256": hashlib.sha256(data).hexdigest(), "bytesConsumed": reader.pos,
            "sourceBytes": len(data), "prototypes": prototypes,
            "unparsedTailHex": reader.take(len(data) - reader.pos).hex()}


if __name__ == "__main__":
    result = decode(Path(sys.argv[1]).read_bytes())
    Path(sys.argv[2]).write_text(json.dumps(result, indent=2) + "\n")
    print("Definitions:", len(result["prototypes"]), "consumed:", result["bytesConsumed"],
          "remaining:", len(result["unparsedTailHex"]) // 2)
