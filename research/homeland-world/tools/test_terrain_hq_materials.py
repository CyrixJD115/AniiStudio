import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

research=Path(__file__).resolve().parent.parent/'Research/2026-10-23'
sectors=[(7,5),(8,5),(7,6),(8,6)]


class TerrainHQMaterialTests(unittest.TestCase):
    def test_all_four_pages_keep_source_world_footprints_and_bounded_batches(self):
        for x,z in sectors:
            folder=research/f'terrain-hq-1024-{x}-{z}'
            if not (folder/'manifest.json').exists():self.skipTest('HQ original-kernel pages unavailable')
            proof=json.loads((folder/'manifest.json').read_text())
            self.assertEqual(proof['sector'],[x,z]);self.assertEqual(proof['resolution'],1032)
            self.assertEqual(proof['logicalPixels'],1024);self.assertEqual(proof['gutterPixels'],4)
            self.assertEqual(proof['batchPixelLimit'],8192);self.assertEqual(proof['batchCount'],131)
            self.assertEqual(proof['sectorUVOrigin'],[-4/1024,-4/1024]);self.assertEqual(proof['sectorUVStep'],1/1024)
            self.assertEqual(proof['worldExtentMetres'],64.5)
            for name in ['diffuse.png','packed-normal.png']:
                with Image.open(folder/name) as image:
                    self.assertEqual(image.size,(1032,1032))

    def test_only_four_native_sectors_change_and_source_hashes_remain_bound(self):
        root=research/'native-terrain-hq-materials'
        if not (root/'manifest.json').exists():self.skipTest('Native HQ materials unavailable')
        manifest=json.loads((root/'manifest.json').read_text())
        baseline={(t['x'],t['z']):t for t in json.loads((research/'native-terrain-materials/manifest.json').read_text())['tiles']}
        self.assertEqual(len(manifest['tiles']),256)
        changed=[]
        for tile in manifest['tiles']:
            key=(tile['x'],tile['z'])
            for role in ['color','normal','roughness']:
                entry=tile[role];self.assertEqual(hashlib.sha256((root/entry['file']).read_bytes()).hexdigest(),entry['sha256'])
            if key in sectors:
                changed.append(key)
                self.assertEqual((tile['logicalPixels'],tile['gutterPixels'],tile['imagePixels']),(1024,4,1032))
                source=research/f'terrain-hq-1024-{key[0]}-{key[1]}/manifest.json'
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),tile['sourceReferenceManifestSHA256'])
            else:
                for role in ['color','normal','roughness']:self.assertEqual(tile[role],baseline[key][role])
        self.assertEqual(set(changed),set(sectors))

    def test_native_mixed_resolution_uvs_and_all_captured_matrices(self):
        path=research/'captured-home-hq-terrain-qa/rendered-world-summary.json'
        if not path.exists():self.skipTest('Native mixed-resolution scene unavailable')
        scene=json.loads(path.read_text());capture=json.loads((research/'residential-world-content/residential-content.json').read_text())
        self.assertEqual({p['id']:p['nativeTransform'] for p in scene['capturedInstances']},
                         {p['id']:p['nativeTransform'] for p in capture['placements']})
        self.assertEqual(scene['terrainTriangles'],513788)
        for tile in scene['nativeTerrainMaterialTransforms']:
            logical=1024 if (tile['sectorX'],tile['sectorZ']) in sectors else 128
            for local in [0,.5,1]:
                expected=(4+logical*local)/(logical+8)
                self.assertAlmostEqual((tile['sectorX']+local)/16*tile['scaleU']+tile['offsetU'],expected,places=6)
                self.assertAlmostEqual((tile['sectorZ']+local)/16*tile['scaleV']+tile['offsetV'],expected,places=6)


if __name__=='__main__':unittest.main()
