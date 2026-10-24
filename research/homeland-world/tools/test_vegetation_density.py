import importlib.util
import os
import json
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("vegetation_density", Path(__file__).with_name("decode-vegetation-density.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VegetationDensityTests(unittest.TestCase):
    def chunk(self, mask, format, words):
        payload = struct.pack("<" + "H"*len(words), *words)
        header = struct.pack("<IHHHBI", mask, 2, 2, format | 2 << 8, 0, len(payload))
        return header + payload + bytes(32) + bytes(8) + bytes(32)

    def test_interleaved_r16_density_and_scale_are_separated(self):
        result = module.decode(self.chunk(5, 72, [0, 24576, 65535, 32768, 100, 40000, 300, 65535]))
        self.assertEqual(result["densityU16"], (0, 65535, 100, 300))
        self.assertEqual(result["scaleU16"], (24576, 32768, 40000, 65535))
        result = module.decode(self.chunk(1, 9, [0, 1, 500, 65535]))
        self.assertIsNone(result["scaleU16"])

    def test_unverified_masks_formats_and_payload_shapes_rejected(self):
        for data in (self.chunk(3, 72, [0]*8), self.chunk(5, 9, [0]*8),
                     self.chunk(1, 72, [0]*4), self.chunk(5, 72, [0]*7)):
            with self.assertRaises(ValueError):
                module.decode(data)

    def test_all_original_grids_validate_against_record_payload_lengths(self):
        if not os.environ.get('ANII_GAME_ROOT'):self.skipTest('Set ANII_GAME_ROOT for installed vegetation fixtures')
        root = Path(os.environ['ANII_GAME_ROOT'])/'AssetsExtra/raw/xrenderPC/RuntimeLevel_FB_Home_01/Vegetation/Chunk'
        if not root.exists():
            self.skipTest("Installed game resources unavailable")
        grids = [module.decode(r["bytes"]) for p in root.glob("*.pack") for r in module.sections.stream.decode(p.read_bytes())]
        grids = [g for g in grids if g is not None]
        self.assertEqual(len(grids), 54)
        self.assertEqual(sum(sum(v > 0 for v in g["densityU16"]) for g in grids), 86251)
        for grid in grids:
            self.assertEqual(len(grid["densityU16"]), grid["width"]*grid["height"])

    def test_original_pattern_reference_and_dimensions_preserved(self):
        research = Path(__file__).resolve().parent.parent / "Research/2026-10-23"
        path = research / "homeland-placement-pattern.json"
        if not path.exists():
            self.skipTest("Local pattern fixture unavailable")
        data = json.loads(path.read_text())
        scene = json.loads((research / "homeland-components-summary.json").read_text())
        self.assertEqual(scene["externalFiles"][12].split("/")[-1], data["sourceCAB"])
        self.assertEqual(data["pathID"], 6675825702353143427)
        self.assertEqual(len(data["data"]["m_Patterns"]), 64)
        for pattern in data["data"]["m_Patterns"]:
            points = [(p["x"], p["y"]) for p in pattern["m_Points"]]
            self.assertEqual(len(set(points)), 64)
            self.assertTrue(all(0 <= v <= 1 for xy in points for v in xy))


if __name__ == "__main__":
    unittest.main()
