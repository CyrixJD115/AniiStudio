import hashlib
import io
import json
from pathlib import Path
import struct
import unittest
from PIL import Image

research=Path(__file__).resolve().parent.parent/"Research/2026-10-23"


class StaticRockModelTests(unittest.TestCase):
    def setUp(self):
        self.root=research/"static-rock-models"
        if not (self.root/"manifest.json").exists():self.skipTest("Local original rock export unavailable")
        self.manifest=json.loads((self.root/"manifest.json").read_text())

    def assets(self):
        for model in self.manifest["models"]:
            for renderer in model["renderers"]:
                data=(self.root/renderer["file"]).read_bytes()
                size,kind=struct.unpack_from("<II",data,12)
                self.assertEqual(kind,0x4e4f534a)
                yield renderer,data,json.loads(data[20:20+size]),data[28+size:]

    def test_all_original_selected_placements_preserved_without_cell_duplicates(self):
        world=json.loads((research/"homeland-static-xbatch-world.json").read_text())
        ids={m["prototypeID"] for m in self.manifest["models"]}
        self.assertEqual(len(ids),24)
        self.assertEqual(self.manifest["failedRenderers"],[])
        expected=[p for p in world["uniqueInstances"] if p["prototypeID"] in ids]
        self.assertEqual(self.manifest["placements"],expected)
        self.assertEqual(len(expected),533)
        self.assertEqual(len({p["sourceInstanceID"] for p in expected}),533)
        self.assertEqual(hashlib.sha256((research/"homeland-static-xbatch-world.json").read_bytes()).hexdigest(),self.manifest["sourceWorldSHA256"])

    def test_every_glb_has_valid_original_geometry_and_primitive_ranges(self):
        for renderer,data,doc,binary in self.assets():
            self.assertEqual(struct.unpack_from("<III",data),(0x46546c67,2,len(data)))
            self.assertEqual(hashlib.sha256(data).hexdigest(),renderer["sha256"])
            qa=renderer["geometryQA"]
            self.assertLessEqual(qa["maxBoundsErrorMetres"],qa["sourceQuantizationStepMetres"]*1.01)
            self.assertEqual(doc["accessors"][0]["count"],qa["vertices"])
            for view in doc["bufferViews"]:self.assertLessEqual(view["byteOffset"]+view["byteLength"],len(binary))
            triangles=0
            for primitive in doc["meshes"][0]["primitives"]:
                accessor=doc["accessors"][primitive["indices"]]
                self.assertEqual(accessor["componentType"],5125)
                view=doc["bufferViews"][accessor["bufferView"]]
                values=struct.unpack_from("<"+"I"*accessor["count"],binary,view["byteOffset"])
                self.assertLess(max(values),qa["vertices"])
                triangles+=accessor["count"]//3
            self.assertEqual(triangles,qa["triangles"])

    def test_packed_original_alpha_never_becomes_opaque_rock_transparency(self):
        for renderer,data,doc,binary in self.assets():
            for slot,material in enumerate(doc["materials"]):
                self.assertEqual(material["alphaMode"],"OPAQUE")
                self.assertEqual(material["pbrMetallicRoughness"]["baseColorFactor"][3],1)
                texture=renderer["geometryQA"]["materials"][slot]["baseTexture"]
                if texture is None:continue
                source=(self.root/texture["file"]).read_bytes()
                self.assertEqual(hashlib.sha256(source).hexdigest(),texture["sha256"])
                image_index=doc["textures"][material["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
                view=doc["bufferViews"][doc["images"][image_index]["bufferView"]]
                embedded=Image.open(io.BytesIO(binary[view["byteOffset"]:view["byteOffset"]+view["byteLength"]]))
                self.assertEqual(embedded.mode,"RGB")
                self.assertEqual(embedded.tobytes(),Image.open(io.BytesIO(source)).convert("RGB").tobytes())


if __name__=="__main__":unittest.main()
