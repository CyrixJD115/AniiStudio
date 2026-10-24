import importlib.util
import json
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('prefab', Path(__file__).with_name('read-xchunk-prefab-packets.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
research = Path(__file__).resolve().parent.parent / 'Research/2026-10-23'


class XChunkPrefabPacketTests(unittest.TestCase):
    def packets(self):
        root = research/'xchunk-prefab-packets'
        if not (root/'manifest.json').exists(): self.skipTest('Local original prefab packets unavailable')
        return [(r['id'], (root/r['file']).read_bytes()) for r in json.loads((root/'manifest.json').read_text())['records']]

    def test_actual_records_preserve_global_resource_indices_and_all13_water_poses(self):
        count = 0; water = []
        for identity, data in self.packets():
            result = module.packet(data, 5)
            self.assertEqual(result['bytesConsumed'], len(data))
            count += len(result['instances'])
            if len(result['resourceIndices']) == 4:
                # Index4 is global into storage, not local into this4-entry list.
                self.assertIn(4, [i['resourceIndex'] for i in result['instances']])
            water.extend(i for i in result['instances'] if i['resourceIndex'] in (3, 4))
            for i in result['instances']:
                raw = bytes.fromhex(i['encodedHex'])
                self.assertEqual(len(raw), 46)
                self.assertEqual(struct.unpack_from('<3f', raw, 1), tuple(i['position']))
                self.assertEqual(struct.unpack_from('<3f', raw, 29), tuple(i['scale']))
        self.assertEqual(count, 32)
        self.assertEqual(len(water), 13)
        large = [p for p in water if p['scale'][0] == 2100]
        self.assertEqual(len(large), 1)
        self.assertEqual(large[0]['scale'], [2100, 1, 1800])
        self.assertAlmostEqual(large[0]['position'][1], 99)

    def test_invalid_stride_resource_id_and_nonunit_quaternion_rejected(self):
        data = self.packets()[0][1]
        with self.assertRaises(ValueError): module.packet(data[:-1], 5)
        with self.assertRaises(ValueError): module.packet(data+b'\0', 5)
        start = 8 + struct.unpack_from('<I', data)[0]
        invalid = bytearray(data); struct.pack_into('<I', invalid, start+42, 5)
        with self.assertRaises(ValueError): module.packet(invalid, 5)
        invalid = bytearray(data); struct.pack_into('<4f', invalid, start+13, 0, 0, 0, 0)
        with self.assertRaises(ValueError): module.packet(invalid, 5)

    def test_water_hierarchies_have_explicit_platform_links_and_identity_roots(self):
        path = research/'homeland-original-water-prefabs.json'
        if not path.exists(): self.skipTest('Local original water prefabs unavailable')
        prefabs = json.loads(path.read_text())['prefabs']
        self.assertEqual(len(prefabs), 2)
        platforms = json.loads((research/'homeland-water-platform-data.json').read_text())['platforms']
        self.assertEqual({p['prefabPath'] for p in platforms}, {p['assetPath'] for p in prefabs})
        for prefab in prefabs:
            links = [c['data']['m_PlatformData'] for c in prefab['root']['components'] if 'm_PlatformData' in c['data']]
            self.assertEqual(len(links), 1)
            platform = next(p for p in platforms if p['prefabPath'] == prefab['assetPath'])
            self.assertEqual(links[0]['m_PathID'], platform['pathID'])
            renderers = platform['data']['m_DefaultConfig']['m_Lods'][0]['m_Renderers']
            self.assertEqual(len(renderers), 1)
            self.assertEqual(len(renderers[0]['m_MaterialList']), 1)
            transform = next(c['data'] for c in prefab['root']['components'] if c['type'] == 'Transform')
            self.assertEqual(transform['m_LocalScale'], dict(x=1, y=1, z=1))
            self.assertEqual(transform['m_LocalPosition'], dict(x=0, y=0, z=0))


if __name__ == '__main__': unittest.main()
