import importlib.util
import json
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('xchunk', Path(__file__).with_name('read-xchunk-storage.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
research = Path(__file__).resolve().parent.parent / 'Research/2026-10-23'


class XChunkStorageTests(unittest.TestCase):
    def source(self, kind):
        path = research/f'xchunk-{kind}-storage/record-root.bin'
        if not path.exists(): self.skipTest('Local original XChunk table unavailable')
        return path.read_bytes()

    def test_actual_collision_paths_cover_all64_original_terrain_tiles_and_packet_directory(self):
        data = self.source('collider'); result = module.storage(data)
        self.assertEqual(result['bytesConsumed'], len(data))
        self.assertEqual(len(result['resources']), 128)
        terrain = result['resources'][:64]
        expected = {f'Terrain_{x}_{z}_CollisionData.asset' for x in range(8) for z in range(8)}
        self.assertEqual({Path(r['path']).name for r in terrain}, expected)
        self.assertEqual({r['opaqueKindU32'] for r in terrain}, {7})
        self.assertEqual({r['opaqueKindU32'] for r in result['resources'][64:]}, {0})
        packets = json.loads((research/'xchunk-collider-packets/manifest.json').read_text())
        self.assertEqual(set(result['packetIDs']), {r['id'] for r in packets['records']})

    def test_prefab_table_keeps_water_and_effect_resources_explicit(self):
        result = module.storage(self.source('prefab'))
        self.assertEqual(len(result['resources']), 5)
        self.assertEqual(len(result['packetIDs']), 2)
        paths = [r['path'] for r in result['resources']]
        self.assertEqual(sum('/Effect/' in p for p in paths), 3)
        self.assertEqual(sum('/Prefab/Static/Art/EPrefab_Water' in p for p in paths), 2)

    def test_all_explicit_unity_references_including_plural_xchunk_are_indexed(self):
        path = research/'homeland-world-reference-links.json'
        if not path.exists(): self.skipTest('Original Unity references unavailable')
        references = json.loads(path.read_text()); indexed = {}
        for path in (research/'environment-asset-index').glob('*.json'):
            for asset in json.loads(path.read_text())['assets']:
                indexed[(asset['cab'].lower(), asset['pathID'])] = asset['path']
        names = []
        for pointer in references['XChunkReference']['data']['m_References']:
            table = references['XChunkReference']
            cab = table['externalFiles'][pointer['m_FileID']-1].split('/')[-1]
            self.assertIn((cab.lower(), pointer['m_PathID']), indexed)
            names.append(indexed[(cab.lower(), pointer['m_PathID'])])
        self.assertEqual(len(names), 7)
        prefab_paths = {a['path'] for a in module.storage(self.source('prefab'))['resources']}
        self.assertTrue(prefab_paths.issubset(set(names)))

    def test_rejects_truncated_trailing_and_malformed_packet_length(self):
        data = self.source('collider')
        for bad in [data[:-1], data+b'\x00']:
            with self.assertRaises(ValueError): module.storage(bad)
        # Source string is63bytes plus its one-byte length, then11header words.
        malformed = bytearray(data); struct.pack_into('<I', malformed, 64+44, 15)
        with self.assertRaises(ValueError): module.storage(malformed)
        duplicate = bytearray(data); duplicate[116:120] = duplicate[112:116]
        with self.assertRaises(ValueError): module.storage(duplicate)


if __name__ == '__main__': unittest.main()
