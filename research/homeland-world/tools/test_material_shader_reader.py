import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import unittest

spec=importlib.util.spec_from_file_location("shader_reader",Path(__file__).with_name("extract-material-shader.py"))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class MaterialShaderReaderTests(unittest.TestCase):
    def parsed(self):
        return {"m_KeywordNames":["TOPPING"],"m_SubShaders":[{"m_Passes":[{
            "progFragment":{"m_PlayerSubPrograms":[[{"m_ShaderCompilerPlatform":4,"m_BlobIndex":0,"m_KeywordIndices":[0]}]],
                            "m_ParameterBlobIndices":[[1]]}}]}]}

    def container(self):
        # Bounded tokenized shader container with one SHDR version/length header.
        return b"DXBC"+bytes(16)+struct.pack("<4I",1,52,1,36)+b"SHDR"+struct.pack("<3I",8,0x10050,2)

    def test_only_explicit_gpu_indices_and_keywords_selected(self):
        refs=module.gpu_references(self.parsed())
        self.assertEqual(set(refs),{(4,0)})
        self.assertEqual(refs[(4,0)][0]["keywords"],["TOPPING"])
        parsed=self.parsed();parsed["m_KeywordNames"]=[]
        with self.assertRaises(ValueError):module.gpu_references(parsed)

    def test_parameter_entry_is_not_read_as_a_gpu_program(self):
        # Parameter entry intentionally exceeds bounds. Valid GPU entry still reads.
        raw=struct.pack("<7I",2,28,4,0,32,10000000,0)+b"GPU!"
        self.assertEqual(module.gpu_entry([raw],0),(0,b"GPU!"))
        with self.assertRaises(ValueError):module.gpu_entry([raw],1)
        with self.assertRaises(ValueError):module.gpu_entry([raw],2)
        corrupt=bytearray(raw);struct.pack_into("<I",corrupt,4,0)
        with self.assertRaises(ValueError):module.gpu_entry([bytes(corrupt)],0)

    def test_realistic_binding_prefix_and_corrupt_container_bounds(self):
        source=self.container()
        self.assertEqual(module.dxbc_container(bytes(66)+source),source)
        for data in (source[:-1],source[:20],source[:24]+struct.pack("<I",1000000)+source[28:]):
            with self.assertRaises(ValueError):module.dxbc_container(data)

    def test_verified_manifests_reference_gpu_entries_not_parameter_blobs(self):
        research=Path(__file__).resolve().parent.parent/"Research/2026-10-23"
        for folder,expected in [("rock-shader-verified",144),("pine-leaf-shader-verified",162),("grass-shader-verified",171)]:
            path=research/folder
            if not (path/"manifest.json").exists():self.skipTest("Verified shader artifacts unavailable")
            manifest=json.loads((path/"manifest.json").read_text())
            refs=module.gpu_references(json.loads((path/"parsed-shader.json").read_text()))
            self.assertEqual(len(manifest["programs"]),expected)
            for row in manifest["programs"]:
                self.assertIn((row["platform"],row["blobIndex"]),refs)
                data=(path/row["file"]).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(),row["sha256"])
                self.assertEqual(module.dxbc_container(data),data)

    def test_previously_used_geometry_and_palette_proofs_match_verified_gpu_bytes(self):
        research=Path(__file__).resolve().parent.parent/"Research/2026-10-23"
        pairs=[("grass-shader-inspection/grass-p4-s0-v7.dxbc","grass-shader-verified/program-p4-s0-v7.dxbc"),
               ("grass-shader-inspection/grass-p4-s0-v8.dxbc","grass-shader-verified/program-p4-s0-v8.dxbc")]
        pairs += [(f"pine-leaf-shader/program-p4-s0-v{i}.dxbc",f"pine-leaf-shader-verified/program-p4-s0-v{i}.dxbc") for i in (4,105,107,109)]
        for old,new in pairs:
            if not (research/old).exists() or not (research/new).exists():self.skipTest("Historical proof artifacts unavailable")
            self.assertEqual((research/old).read_bytes(),(research/new).read_bytes())


if __name__=="__main__":unittest.main()
