import importlib.util
import json
import math
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("environment_vertices", Path(__file__).with_name("decode-environment-vertices.py"))
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)


class EnvironmentVertexTests(unittest.TestCase):
    def test_quantized_position_extents_follow_packed_range_bits(self):
        for bits in range(8):
            position, normal, uv = codec.decode([0, 65535, 0, (2048 << 4) | bits << 1],
                                               [2048 << 4, 0], [0, 65535])
            extent = 2**(3+bits)
            self.assertEqual(position, [-extent, extent, -extent])
            self.assertAlmostEqual(sum(v*v for v in normal), 1)
            self.assertAlmostEqual(uv[0], -16)
            self.assertAlmostEqual(uv[1], 16, places=5)

    def test_octahedral_fold_recovers_negative_z(self):
        _, normal, _ = codec.decode([0, 0, 0, 4095 << 4], [4095 << 4, 0], [0, 0])
        self.assertEqual(normal, [0, 0, -1])

    def test_invalid_source_attributes_rejected(self):
        for position in ([0, 0, 0], [0, 0, 0, -1], [0, 0, 0, 65536], [0, 0, 0, 1.2]):
            with self.assertRaises(ValueError):
                codec.decode(position, [0, 0], [0, 0])

    def test_original_export_has_bounded_glb_and_valid_geometry(self):
        path = Path(__file__).resolve().parent.parent / "Research/2026-10-23/environment-model-qa/original-home-grass-lod0.glb"
        if not path.exists():
            self.skipTest("Local export unavailable")
        data = path.read_bytes()
        self.assertEqual(struct.unpack_from("<III", data), (0x46546c67, 2, len(data)))
        length, kind = struct.unpack_from("<II", data, 12)
        self.assertEqual(kind, 0x4e4f534a)
        doc = json.loads(data[20:20+length])
        binary_length, binary_kind = struct.unpack_from("<II", data, 20+length)
        self.assertEqual(binary_kind, 0x004e4942)
        self.assertEqual(28+length+binary_length, len(data))
        self.assertEqual(doc["accessors"][0]["count"], 120)
        self.assertEqual(doc["accessors"][3]["count"], 180)
        self.assertTrue(doc["materials"][0]["doubleSided"])
        binary = data[28+length:]
        for view in doc["bufferViews"]:
            self.assertLessEqual(view["byteOffset"]+view["byteLength"], len(binary))
        view = doc["bufferViews"][doc["accessors"][1]["bufferView"]]
        values = struct.unpack_from("<360f", binary, view["byteOffset"])
        self.assertLess(max(abs(sum(v*v for v in values[i:i+3])-1) for i in range(0,360,3)), 1e-6)


if __name__ == "__main__":
    unittest.main()
