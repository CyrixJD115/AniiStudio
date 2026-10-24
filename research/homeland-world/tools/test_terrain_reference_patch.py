import hashlib
import json
from pathlib import Path
import unittest
import numpy as np
from PIL import Image

research=Path(__file__).resolve().parent.parent/'Research/2026-10-23'


class TerrainReferencePatchTests(unittest.TestCase):
    def test_real_patch_is_source_bound_finite_and_keeps_packed_channels(self):
        folder=research/'terrain-reference-home-patch'
        if not (folder/'manifest.json').exists():self.skipTest('Offline source-map patch unavailable')
        report=json.loads((folder/'manifest.json').read_text())
        shader=research/'terrain-bake-shader-inspection/XTerrainBakePhysicalPage-0-CSMainWithVT-0.dxbc'
        self.assertEqual(hashlib.sha256(shader.read_bytes()).hexdigest(),report['shaderSHA256'])
        self.assertEqual(report['centerWorldXZ'],[32,-135.5])
        self.assertIn('NOT live-verified',report['scope'])
        for name in ['diffuse','packed-normal']:
            image=Image.open(folder/f'{name}.png').convert('RGBA');pixels=np.asarray(image)
            self.assertEqual(image.size,(64,64))
            self.assertGreater(int(pixels.max())-int(pixels.min()),0)
            self.assertTrue(np.all(pixels[:,:,3]<255))
            self.assertTrue(all(np.isfinite(report['statistics'][name][bound]).all() for bound in ['minimum','maximum']))
        color=np.asarray(Image.open(folder/'diffuse.png').convert('RGB'))
        self.assertTrue(np.all(color[:,:,1]>color[:,:,0]))
        self.assertTrue(np.all(color[:,:,1]>color[:,:,2]))


if __name__=='__main__':unittest.main()
