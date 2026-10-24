import hashlib
import json
from pathlib import Path
import struct
import unittest

research = Path(__file__).resolve().parent.parent / 'Research/2026-10-23'


class PineVariantTests(unittest.TestCase):
    def setUp(self):
        self.root = research / 'environment-model-qa'
        if not (self.root/'pine-variants.json').exists():
            self.skipTest('Local original pine variants unavailable')
        self.manifest = json.loads((self.root/'pine-variants.json').read_text())

    def test_distinct_original_models_match_independent_mesh_bounds_and_indices(self):
        metadata = json.loads((research/'homeland-vegetation-mesh-metadata.json').read_text())['meshes']
        expected = {5: (4922, 3773), 27: (2679, 2311)}
        for model in self.manifest['models']:
            path = self.root/model['file']; data = path.read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), model['sha256'])
            self.assertEqual(struct.unpack_from('<III', data), (0x46546c67, 2, len(data)))
            length = struct.unpack_from('<I', data, 12)[0]
            doc = json.loads(data[20:20+length]); binary = data[28+length:]
            proof = json.loads(path.with_suffix('.provenance.json').read_text())
            source = metadata[proof['explicitCurrentMesh']]
            vertices, triangles = expected[model['prototypeID']]
            self.assertEqual(doc['accessors'][0]['count'], vertices)
            self.assertEqual(proof['vertices'], source['vertexCount'])
            self.assertEqual(proof['triangles'], triangles)
            for axis, original_axis in enumerate('zyx'):
                center = source['bounds']['m_Center'][original_axis]
                extent = source['bounds']['m_Extent'][original_axis]
                self.assertAlmostEqual(doc['accessors'][0]['min'][axis], center-extent, delta=proof['sourcePositionQuantizationStepMetres']*2)
                self.assertAlmostEqual(doc['accessors'][0]['max'][axis], center+extent, delta=proof['sourcePositionQuantizationStepMetres']*2)
            for primitive in doc['meshes'][0]['primitives']:
                accessor = doc['accessors'][primitive['indices']]
                view = doc['bufferViews'][accessor['bufferView']]
                indices = struct.unpack_from('<'+'H'*accessor['count'], binary, view['byteOffset'])
                self.assertLess(max(indices), vertices)
            self.assertEqual(doc['materials'][0]['alphaMode'], 'MASK')
            self.assertTrue(doc['materials'][0]['doubleSided'])

    def test_manifest_ids_and_counts_match_unchanged_original_chunk_records(self):
        chunks = json.loads((research/'homeland-vegetation-transforms.json').read_text())['chunks']
        definitions = {p['id']: p for p in json.loads((research/'homeland-vegetation-stream-definitions.json').read_text())['prototypes']}
        self.assertEqual({m['prototypeID'] for m in self.manifest['models']}, {5, 27})
        total = 0
        for model in self.manifest['models']:
            prototype = model['prototypeID']
            self.assertEqual(model['prefab'], definitions[prototype]['name'])
            self.assertEqual(definitions[prototype]['materialLODs'][0], definitions[7]['materialLODs'][0])
            count = sum(len(c['instances']) for c in chunks if c['prototypeID'] == prototype)
            self.assertEqual(model['sourcePlacements'], count)
            total += count
        self.assertEqual(total, 293)


if __name__ == '__main__': unittest.main()
