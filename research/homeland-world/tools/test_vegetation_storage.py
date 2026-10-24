import importlib.util
import os
import json
from pathlib import Path
import struct
import unittest


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


module = load("vegetation_storage_tests", "read-vegetation-storage.py")
chunks = load("vegetation_chunk_tests", "inspect-vegetation-chunks.py")
world = Path.home() / "Library/Application Support/AniimoAtlas/Environment/World"
research = Path(__file__).resolve().parent.parent / "Research/2026-10-23"


class VegetationStorageTests(unittest.TestCase):
    def test_invalid_strings_counts_and_nonfinite_values_are_rejected(self):
        for data in (b"\xff" * 5, b"\x80", b"\x03ab"):
            with self.assertRaises((ValueError, UnicodeError)):
                module.Reader(data).string()
        with self.assertRaises(ValueError):
            module.Reader(struct.pack("<I", 5000)).count()
        with self.assertRaises(ValueError):
            module.Reader(struct.pack("<f", float("nan"))).number("f")

    def test_runtime_prototype_ids_and_settings_match_independent_odin_source(self):
        path = world / "Streaming/VegetationStorage/record-root.bin"
        odin_path = research / "homeland-vegetation-decoded.json"
        if not path.exists() or not odin_path.exists():
            self.skipTest("Local source fixtures unavailable")
        actual = module.decode(path.read_bytes())
        expected = json.loads(odin_path.read_text())["entries"][0]["children"][0]["children"]
        self.assertEqual(len(actual["prototypes"]), 21)
        for runtime, source in zip(actual["prototypes"], expected):
            fields = {f.get("name"): f for f in source["children"]}
            self.assertEqual(runtime["id"], fields["m_Index"]["children"][0]["value"])
            self.assertEqual(runtime["name"], fields["m_PrefabName"]["value"])
            for key in ("vegetationType", "castShadow", "enableCollision", "overrideDensityCurve",
                        "density", "useNormalDirection", "overrideSlopeLimit", "slopeLimit",
                        "enableRandomRotation", "rotateMin", "rotateMax", "enableRandomScale",
                        "scaleMin", "scaleMax", "enableCustomCullDistance", "customCullDistance",
                        "influenceGrassTex", "grassTexHeightScale", "useLodCull", "lodFactor",
                        "enableCrossFade", "collisionBoundingScale", "dyeingLayer", "pcOnly",
                        "batchGroup", "isBatchGroupLeader"):
                field = "m_" + key[0].upper() + key[1:]
                self.assertEqual(runtime[key], fields[field]["value"], (runtime["id"], key))
            self.assertTrue(all(p.startswith("Assets/Res_Export/Environment/Mesh/PC/")
                                for lod in runtime["meshLODs"] for p in lod))
            self.assertEqual(len(runtime["meshLODs"]), len(runtime["materialLODs"]))
        # Definitions consumed exactly; the remaining group/stream metadata stays explicitly opaque.
        self.assertEqual(actual["bytesConsumed"], 24905)
        self.assertEqual(len(bytes.fromhex(actual["unparsedTailHex"])), 462)

    def test_all_installed_chunk_sections_validate_without_guessing_unknown_ids(self):
        if not os.environ.get('ANII_GAME_ROOT'):self.skipTest('Set ANII_GAME_ROOT for installed vegetation fixtures')
        root = Path(os.environ['ANII_GAME_ROOT'])/'AssetsExtra/raw/xrenderPC/RuntimeLevel_FB_Home_01/Vegetation/Chunk'
        if not root.exists():
            self.skipTest("Installed scenery unavailable")
        files = list(root.glob("*.pack"))
        self.assertEqual(len(files), 59)
        records = [chunks.decode(e["bytes"]) for f in files for e in chunks.stream.decode(f.read_bytes())]
        self.assertEqual(len(records), 182)
        self.assertEqual(sum(r["packedInstanceCount"] for r in records), 3982)

    def test_actual_chunks_consumed_and_instance_lengths_crosscheck(self):
        root = world / "Streaming/VegetationChunk0-0"
        if not root.exists():
            self.skipTest("Local source fixtures unavailable")
        for path in root.glob("record-*.bin"):
            data = path.read_bytes()
            result = chunks.decode(data)
            self.assertEqual(result["opaqueInstances"]["byteLength"], result["packedInstanceCount"] * 16)
            with self.assertRaises(ValueError):
                chunks.decode(data[:-1])
            with self.assertRaises(ValueError):
                chunks.decode(data + b"\x00")

    def test_mismatched_instance_index_payload_rejected(self):
        # No grid, empty grid bounds, one packed instance, no corresponding index.
        data = bytes(36) + struct.pack("<I", 16) + bytes(16) + bytes(4) + bytes(32)
        with self.assertRaises(ValueError):
            chunks.decode(data)


if __name__ == "__main__":
    unittest.main()
