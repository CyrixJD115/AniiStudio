import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location('material_texels', Path(__file__).with_name('decode-terrain-material-texels.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
research = Path(__file__).resolve().parent.parent/'Research/2026-10-23'


class TerrainMaterialTexelTests(unittest.TestCase):
    def test_weight_selects_second_layer_and_rotation_bytes_are_not_layer_ids(self):
        first = module.texel([11,111,6,59], 0, 15)
        second = module.texel([11,111,6,59], 255, 15)
        self.assertEqual((first['layer0'], first['layer1']), (11,6))
        self.assertEqual((first['rotation0Byte'], first['rotation1Byte']), (111,59))
        self.assertEqual(first['layer1Weight'], 0)
        self.assertEqual(second['layer1Weight'], 1)
        self.assertAlmostEqual(module.texel([0,0,1,0],128,15)['layer1Weight'],128/255)
        with self.assertRaises(ValueError): module.texel([15,0,0,0],0,15)
        with self.assertRaises(ValueError): module.texel([0,-1,0,0],0,15)

    def test_rotation_follows_source_parabolic_approximation_not_normalized_trigonometry(self):
        for byte, expected in [(0,(1,0)), (64,(0,1)), (128,(-1,0)), (192,(0,-1))]:
            self.assertEqual(module.fast_rotation(byte), expected)
        self.assertEqual(module.fast_rotation(32), (.75,.75))
        with self.assertRaises(ValueError): module.fast_rotation(256)

    def test_home_world_center_resolves_to_source_grass_layer_and_full_weight(self):
        path = research/'homeland-terrain-sector-records.json'
        if not path.exists(): self.skipTest('Local original terrain sectors unavailable')
        area = json.loads((research/'homeland-area-static.json').read_text())['1']['areaCenter']
        x,z = int((area['1']+512)//64), int((area['3']+512)//64)
        record = next(r for r in json.loads(path.read_text())['records'] if (r['level'],r['x'],r['z'])==(0,x,z))
        data = (research/record['recordFile']).read_bytes()
        def array(role, shape):
            meta = record['maps'][role]
            return np.frombuffer(data[meta['offset']:meta['offset']+meta['bytes']], dtype=np.uint8).reshape(shape)
        col = round((area['1']-(-512+x*64))*2)
        row = round((area['3']-(-512+z*64))*2)
        decoded = module.texel(array('index',(129,129,4))[row,col].tolist(), int(array('weight',(129,129))[row,col]), 15)
        self.assertEqual(decoded, dict(layer0=0,rotation0Byte=59,layer1=1,rotation1Byte=59,layer1Weight=1))

    def test_audit_covers_every_material_texel_and_retains_source_program_hash(self):
        path = research/'homeland-terrain-material-texels.json'
        if not path.exists(): self.skipTest('Local shader/material audit unavailable')
        audit = json.loads(path.read_text())
        self.assertEqual(audit['sectorCount'], 256)
        self.assertEqual(audit['texelCount'], 256*129*129)
        for sector in audit['sectors']:
            self.assertAlmostEqual(sum(sector['unfilteredMaterialContributions'].values()), 1)
        shader = research/'terrain-bake-shader-inspection/XTerrainBakePhysicalPage-0-CSMainWithVT-0.dxbc'
        self.assertEqual(hashlib.sha256(shader.read_bytes()).hexdigest(), audit['programSHA256'])


if __name__ == '__main__': unittest.main()
