import hashlib
import os
import importlib.util
import json
from pathlib import Path
import struct
import unittest
from PIL import Image
import texture2ddecoder


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


textures = load('terrain_textures', 'decode-terrain-layer-textures.py')
root_reader = load('terrain_root', 'read-runtime-terrain-root.py')
research = Path(__file__).resolve().parent.parent/'Research/2026-10-23'
source = Path(os.environ['ANII_GAME_ROOT'])/'AssetsExtra/raw/xrenderPC/RuntimeLevel_FB_Home_01/XTerrain' if os.environ.get('ANII_GAME_ROOT') else None


class TerrainLayerStreamTests(unittest.TestCase):
    def test_runtime_root_matches_all15_independent_diffuse_normal_layers(self):
        path = research/'terrain-runtime-root/record-root.bin'
        if not path.exists(): self.skipTest('Original streamed root unavailable')
        data = path.read_bytes(); root = root_reader.decode(data)
        manifest = json.loads((research/'terrain-layer-textures/manifest.json').read_text())
        self.assertEqual(root['bytesConsumed'], len(data))
        self.assertEqual(root['layerCount'], 15)
        self.assertEqual(len(root['sectorLayerSpans']), 256)
        self.assertEqual(len(root['layerIndexList']), 237)
        for family, descriptor in [('Diffuse', root['diffuseDescriptor']), ('Normal', root['normalDescriptor'])]:
            rows = [r for r in manifest['textures'] if r['kind']==family]
            self.assertEqual({r['layerIndex'] for r in rows}, set(range(15)))
            for row in rows:
                self.assertEqual((row['width'], row['height'], row['format'], row['sourceFlagsU8']),
                                 (descriptor['width'], descriptor['height'], descriptor['format'], descriptor['packedFlagsU8']))
        self.assertEqual(int.from_bytes(bytes(root['opaqueValidLayerMaskBytes']), 'little'), (1<<15)-1)
        for span in root['sectorLayerSpans']:
            self.assertEqual(span['layerIndices'], root['layerIndexList'][span['offset']:span['offset']+span['count']])
        for bad in [data[:-1], data+b'\0']:
            with self.assertRaises(ValueError): root_reader.decode(bad)

    def test_original_mip_chains_and_channel_order_are_preserved(self):
        if source is None or not source.exists(): self.skipTest('Set ANII_GAME_ROOT for installed original terrain textures')
        for kind in ['Diffuse', 'Normal']:
            path = source/f'{kind}TextureArray/{kind}-0.bytes'; data = path.read_bytes(); result = textures.decode(data)
            self.assertEqual((result['width'], result['height']), (1024, 1024))
            self.assertEqual(len(result['mips']), 11)
            self.assertEqual(len(result['blocks']), 1398128)
            self.assertEqual(sum(m['bytes'] for m in result['mips']), len(result['blocks']))
            saved = research/f'terrain-layer-textures/{kind}-0.bc7-mips'
            self.assertEqual(saved.read_bytes(), result['blocks'])
            decoded = texture2ddecoder.decode_bc7(result['blocks'][:1024*1024], 1024, 1024)
            expected = Image.frombytes('RGBA', (1024,1024), decoded, 'raw', 'BGRA')
            actual = Image.open(research/f'terrain-layer-textures/{kind}-0.png').convert('RGBA')
            self.assertEqual(expected.tobytes(), actual.tobytes())

    def test_texture_frame_size_dimensions_and_truncation_are_bounded(self):
        path = source/'DiffuseTextureArray/Diffuse-0.bytes'
        if not path.exists(): self.skipTest('Installed original texture unavailable')
        data = path.read_bytes()
        for bad in [data[:-1], data+b'\0']:
            with self.assertRaises(ValueError): textures.decode(bad)
        bad = bytearray(data); struct.pack_into('<I', bad, 12, textures.LIMIT+1)
        with self.assertRaises(ValueError): textures.decode(bad)
        bad = bytearray(data); struct.pack_into('<H', bad, 2, 512)
        with self.assertRaises(ValueError): textures.decode(bad)


if __name__ == '__main__': unittest.main()
