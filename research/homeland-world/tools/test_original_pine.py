import hashlib
import json
from pathlib import Path
import struct
import unittest
from PIL import Image

research = Path(__file__).resolve().parent.parent / "Research/2026-10-23"


class OriginalPineTests(unittest.TestCase):
    def setUp(self):
        self.path = research / "environment-model-qa/original-home-pine-lod0.glb"
        if not self.path.exists():
            self.skipTest("Local original pine export unavailable")
        self.data = self.path.read_bytes()
        length = struct.unpack_from("<I", self.data, 12)[0]
        self.doc = json.loads(self.data[20:20+length])
        self.binary = self.data[28+length:]

    def test_current_reference_geometry_and_primitive_indices(self):
        self.assertEqual(struct.unpack_from("<III", self.data), (0x46546c67, 2, len(self.data)))
        primitives = self.doc["meshes"][0]["primitives"]
        self.assertEqual(len(primitives), 2)
        self.assertEqual(self.doc["accessors"][0]["count"], 5548)
        self.assertEqual([self.doc["accessors"][p["indices"]]["count"] for p in primitives], [8952,3894])
        for p in primitives:
            a = self.doc["accessors"][p["indices"]]
            view = self.doc["bufferViews"][a["bufferView"]]
            indices = struct.unpack_from("<"+"H"*a["count"], self.binary, view["byteOffset"])
            self.assertLess(max(indices),5548)
        report = json.loads(self.path.with_suffix(".provenance.json").read_text())
        self.assertIn("SM_Tree_Pine_001_B_LOD0",report["explicitCurrentMesh"])
        self.assertEqual(hashlib.sha256(self.data).hexdigest(),report["outputSHA256"])
        self.assertLessEqual(report["maxGeometryBoundsErrorMetres"],report["sourcePositionQuantizationStepMetres"])

    def test_original_alpha_preserved_in_static_palette_image(self):
        alpha = Image.open(research / "pine-textures/leaf/_AlphaMap.png").convert("L")
        baked = Image.open(research / "environment-model-qa/pine-leaf-static-palette.png").convert("RGBA")
        self.assertEqual(alpha.size,baked.size)
        self.assertEqual(alpha.tobytes(),baked.getchannel("A").tobytes())
        visible = [rgb for rgb in baked.getdata() if rgb[3]>128]
        # The source blue-tinted data map must not be rendered as blue foliage.
        self.assertGreater(sum(v[1] for v in visible),sum(v[2] for v in visible))
        leaf = self.doc["materials"][0]
        self.assertEqual(leaf["alphaMode"],"MASK")
        self.assertTrue(leaf["doubleSided"])
        self.assertAlmostEqual(leaf["alphaCutoff"],0.2)

    def test_decoded_normals_and_buffer_views_are_valid(self):
        for view in self.doc["bufferViews"]:
            self.assertLessEqual(view["byteOffset"]+view["byteLength"],len(self.binary))
        normal = self.doc["accessors"][1]
        view = self.doc["bufferViews"][normal["bufferView"]]
        values = struct.unpack_from("<"+"f"*(normal["count"]*3),self.binary,view["byteOffset"])
        self.assertLess(max(abs(sum(v*v for v in values[i:i+3])-1) for i in range(0,len(values),3)),1e-6)


if __name__ == "__main__":
    unittest.main()
