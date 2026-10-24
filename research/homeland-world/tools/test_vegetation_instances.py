import importlib.util
import math
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("vegetation_instances", Path(__file__).with_name("decode-vegetation-instances.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VegetationInstanceTests(unittest.TestCase):
    def test_identity_fixture_checks_biased_coordinates_and_missing_w(self):
        # Independent bit-field fixture derived from the saved original shader instructions:
        # 20 X bits, 20 Z bits, 18 split Y bits; quaternion omits W with positive sign.
        x, y, z = (4096 + 12.5) * 128, (1024 + 100) * 128, (4096 - 7.25) * 128
        data = struct.pack("<4I", (1024 << 20) | int(x), ((int(y) & 4095) << 20) | int(z),
                           ((int(y) >> 12) << 16) | 0xc000, 0xc000c000)
        result = module.decode(data)
        self.assertEqual(result["position"], [12.5, 100, -7.25])
        self.assertEqual(result["rotationXYZW"], [0, 0, 0, 1])
        center, extent = module.transformed_bounds(result, {"center": [1, 2, 3], "extents": [4, 5, 6]})
        scale = result["uniformScale"]
        self.assertEqual(center, [12.5+scale, 100+2*scale, -7.25+3*scale])
        self.assertEqual(extent, [4*scale, 5*scale, 6*scale])

    def test_original_single_bush_matches_independent_saved_bounds(self):
        result = module.decode(bytes.fromhex("d710f833c605981cb9862340834943e0"))
        self.assertEqual(result["position"], [33.6796875, 99.5703125, 11.546875])
        self.assertAlmostEqual(result["uniformScale"], 0.8117216229438782, places=6)
        center, extent = module.transformed_bounds(result, {
            "center": [0.09380209445953369, 1.2113460302352905, -0.010125041007995605],
            "extents": [1.5885809659957886, 1.2708381414413452, 1.6051428318023682]})
        original_center = [33.40483856201172, 100.50640106201172, 11.632397651672363]
        original_extent = [1.9943771362304688, 1.3906326293945312, 1.9498109817504883]
        self.assertLess(max(abs(a-b) for a,b in zip(center+extent, original_center+original_extent)), 0.012)
        self.assertAlmostEqual(sum(q*q for q in result["rotationXYZW"]), 1)

    def test_invalid_length_and_nonunit_compression_rejected(self):
        for data in (bytes(15), bytes(17), bytes([255])*16):
            with self.assertRaises(ValueError):
                module.decode(data)


if __name__ == "__main__":
    unittest.main()
