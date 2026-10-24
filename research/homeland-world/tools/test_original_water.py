import hashlib
import json
from pathlib import Path
import struct
import unittest
import numpy as np

research = Path(__file__).resolve().parent.parent / 'Research/2026-10-23'


class OriginalWaterTests(unittest.TestCase):
    def setUp(self):
        self.root = research/'original-water-models'
        if not (self.root/'manifest.json').exists(): self.skipTest('Original water export unavailable')
        self.manifest = json.loads((self.root/'manifest.json').read_text())

    def test_original_meshes_indices_bounds_and_source_material_swatch(self):
        expected = {3: (19, 18), 4: (4, 2)}
        self.assertEqual({m['resourceIndex'] for m in self.manifest['models']}, set(expected))
        for model in self.manifest['models']:
            data = (self.root/model['file']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), model['sha256'])
            self.assertEqual(struct.unpack_from('<III', data), (0x46546c67, 2, len(data)))
            length = struct.unpack_from('<I', data, 12)[0]; doc = json.loads(data[20:20+length]); binary = data[28+length:]
            vertices, triangles = expected[model['resourceIndex']]
            self.assertEqual(doc['accessors'][0]['count'], vertices)
            self.assertEqual(doc['accessors'][3]['count'], triangles*3)
            for view in doc['bufferViews']: self.assertLessEqual(view['byteOffset']+view['byteLength'], len(binary))
            view = doc['bufferViews'][doc['accessors'][3]['bufferView']]
            indices = struct.unpack_from('<'+'I'*(triangles*3), binary, view['byteOffset'])
            self.assertLess(max(indices), vertices)
            self.assertLessEqual(model['maxBoundsErrorMetres'], model['sourceQuantizationStepMetres']*1.01)
            for axis, source_axis in enumerate('zyx'):
                bounds = model['sourceBounds']; low = bounds['m_Center'][source_axis]-bounds['m_Extent'][source_axis]
                high = bounds['m_Center'][source_axis]+bounds['m_Extent'][source_axis]
                self.assertAlmostEqual(doc['accessors'][0]['min'][axis], low, delta=model['sourceQuantizationStepMetres']*2)
                self.assertAlmostEqual(doc['accessors'][0]['max'][axis], high, delta=model['sourceQuantizationStepMetres']*2)
            colors = dict(model['sourceMaterial']['data']['m_SavedProperties']['m_Colors'])
            self.assertEqual(doc['materials'][0]['pbrMetallicRoughness']['baseColorFactor'], [colors['_SurfaceOverlay0'][k] for k in 'rgba'])

    def test_all13_exported_poses_equal_source_records_without_snapping(self):
        source = json.loads((research/'homeland-xchunk-prefab-placements.json').read_text())
        paths = {m['prefabPath'] for m in self.manifest['models']}
        expected = [{'packetID': p['packetID'], **i} for p in source['packets'] for i in p['instances'] if i['assetPath'] in paths]
        self.assertEqual(self.manifest['placements'], expected)
        self.assertEqual(len(expected), 13)
        self.assertEqual(hashlib.sha256((research/'homeland-xchunk-prefab-placements.json').read_bytes()).hexdigest(), self.manifest['sourcePlacementsSHA256'])

    def test_native_water_matrices_match_independent_full_basis_conjugation(self):
        path = research/'terrain-original-water-qa/rendered-world-summary.json'
        if not path.exists(): self.skipTest('Native water QA not rendered yet')
        summary = json.loads(path.read_text()); actual = {r['identity']: r for r in summary['waterInstances']}
        self.assertEqual(len(actual), 13)
        area = json.loads((research/'homeland-area-static.json').read_text())['1']['areaCenter']
        basis = np.array([[0,0,1], [0,1,0], [1,0,0]])
        for placement in self.manifest['placements']:
            identity = f"{placement['packetID']}/{placement['ordinal']}"
            x,y,z,w = placement['rotationXYZW']
            rotation = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                                 [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                                 [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
            expected = np.eye(4)
            expected[:3,:3] = basis @ rotation @ np.diag(placement['scale']) @ basis
            expected[:3,3] = basis @ (np.array(placement['position'])-np.array([area['1'], area['2'], area['3']])) + np.array([16.637,0,29.584])
            native = np.array(actual[identity]['nativeTransform']).reshape(4,4).T
            np.testing.assert_allclose(native, expected, rtol=1e-5, atol=0.0002)
        self.assertEqual(summary['pineInstances'], 1528)
        self.assertEqual(summary['rockInstances'], 533)
        self.assertEqual(summary['grassInstances'], 1735)


if __name__ == '__main__': unittest.main()
