import importlib.util
import json
import math
from pathlib import Path
import unittest
from PIL import Image

spec=importlib.util.spec_from_file_location("rock_normal",Path(__file__).with_name("decode-rock-normal.py"))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class RockNormalTests(unittest.TestCase):
    def test_rg_and_alpha_green_encodings_share_original_formula(self):
        rgba=module.decode_pixel(.75,.5,1)
        ag=module.decode_pixel(1,.5,.75)
        self.assertEqual(rgba,ag)
        self.assertAlmostEqual(rgba[0],.5)
        self.assertAlmostEqual(rgba[2],math.sqrt(.75))
        scaled=module.decode_pixel(.75,.5,1,.5)
        self.assertAlmostEqual(sum(v*v for v in scaled),1)
        self.assertAlmostEqual(scaled[0],.25/math.sqrt(.25**2+.75))

    def test_image_negates_normal_y_for_flipped_gltf_uv(self):
        image=Image.new("RGBA",(1,1),(255,191,0,255))
        result=module.decode_image(image)
        self.assertLess(result.getpixel((0,0))[1],128)
        with self.assertRaises(ValueError):module.decode_pixel(2,.5,1)
        with self.assertRaises(ValueError):module.decode_pixel(.5,.5,1,float("nan"))

    def test_exported_normals_are_linked_to_verified_source_shader(self):
        research=Path(__file__).resolve().parent.parent/"Research/2026-10-23"
        path=research/"static-rock-models/manifest.json"
        if not path.exists():self.skipTest("Local world models unavailable")
        manifest=json.loads(path.read_text());count=0
        for model in manifest["models"]:
            for renderer in model["renderers"]:
                for material in renderer["geometryQA"]["materials"]:
                    if "primaryNormal" not in material:continue
                    normal=material["primaryNormal"];count+=1
                    self.assertEqual(normal["sourceShaderSHA256"],json.loads((research/"rock-shader-verified/manifest.json").read_text())["sourceSHA256"])
                    image=Image.open(path.parent/normal["file"])
                    source=Image.open(path.parent/normal["source"]["file"])
                    self.assertEqual(image.size,source.size)
                    expected=module.decode_image(source,normal["scale"])
                    self.assertEqual(image.tobytes(),expected.tobytes())
        self.assertGreater(count,0)


if __name__=="__main__":unittest.main()
