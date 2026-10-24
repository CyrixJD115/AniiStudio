import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import numpy as np

spec=importlib.util.spec_from_file_location('native_terrain',Path(__file__).with_name('export-native-terrain-materials.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
research=Path(__file__).resolve().parent.parent/'Research/2026-10-23'


class NativeTerrainMaterialTests(unittest.TestCase):
    def test_shader_decode_uses_squared_color_reconstructed_normal_and_no_opacity(self):
        diffuse=np.array([[[128,64,192,33]],[[64,128,64,77]]],dtype=np.uint8)
        normal=np.array([[[128,128,17,190]],[[128,128,250,80]]],dtype=np.uint8)
        color,normals,rough=module.native_maps(diffuse,normal)
        self.assertEqual(color.shape,(2,1,3))
        self.assertEqual(normals[:,:,2].tolist(),[[255],[255]])
        self.assertEqual(rough[:,0].tolist(),[80,190])
        encoded=color[::-1].astype(float)/255
        decoded=np.where(encoded<=.04045,encoded/12.92,((encoded+.055)/1.055)**2.4)
        np.testing.assert_allclose(decoded,(diffuse[:,:,:3]/255)**2,atol=.004)

    def test_all256_sector_materials_are_checksum_bound_and_complete(self):
        folder=research/'native-terrain-materials'
        if not (folder/'manifest.json').exists():self.skipTest('Original native material derivatives unavailable')
        manifest=json.loads((folder/'manifest.json').read_text())
        self.assertEqual({(t['x'],t['z']) for t in manifest['tiles']},{(x,z) for x in range(16) for z in range(16)})
        self.assertEqual((manifest['logicalPixels'],manifest['gutterPixels'],manifest['imagePixels']),(128,4,136))
        for tile in manifest['tiles']:
            for role in ['color','normal','roughness']:
                entry=tile[role];self.assertEqual(hashlib.sha256((folder/entry['file']).read_bytes()).hexdigest(),entry['sha256'])

    def test_independent_holdout_atlases_and_border_errors_remain_close_to_shipped_data(self):
        path=research/'terrain-atlas-reference-verification/manifest.json'
        if not path.exists():self.skipTest('Independent original-atlas comparison unavailable')
        result=json.loads(path.read_text());self.assertEqual(len(result['sectors']),3)
        for sector in result['sectors']:
            self.assertEqual(sector['uniforms'],result['sectors'][0]['uniforms'])
            self.assertEqual(sector['quadUV'],result['sectors'][0]['quadUV'])
            for comparison in sector['comparisons'].values():
                self.assertLess(max(comparison['channelMAE']),3)
        for seam in result['eightPixelOverlapSeams']:
            self.assertLess(max(abs(a-b) for a,b in zip(seam['referenceChannelMAE'],seam['originalChannelMAE'])),.3)

    def test_native_sector_uvs_match_source_gutters_and_keep_all_captured_transforms(self):
        path=research/'captured-home-native-materials-qa/rendered-world-summary.json'
        if not path.exists():self.skipTest('Native material scene not rendered yet')
        scene=json.loads(path.read_text());capture=json.loads((research/'residential-world-content/residential-content.json').read_text())
        self.assertEqual(scene['nativeTerrainMaterials'],256)
        self.assertEqual({p['id']:p['nativeTransform'] for p in scene['capturedInstances']},
                         {p['id']:p['nativeTransform'] for p in capture['placements']})
        self.assertEqual(scene['terrainTriangles'],513788)
        self.assertEqual(scene['captureSHA256'],capture['captureSHA256'])
        for tile in scene['nativeTerrainMaterialTransforms']:
            for local in [0,.5,1]:
                u=(tile['sectorX']+local)/16
                v=(tile['sectorZ']+local)/16
                expected=(4+128*local)/136
                self.assertAlmostEqual(u*tile['scaleU']+tile['offsetU'],expected,places=6)
                self.assertAlmostEqual(v*tile['scaleV']+tile['offsetV'],expected,places=6)


if __name__=='__main__':unittest.main()
