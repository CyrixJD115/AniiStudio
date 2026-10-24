import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('terrain_sector', Path(__file__).with_name('read-terrain-sector-records.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
research = Path(__file__).resolve().parent.parent/'Research/2026-10-23'


class TerrainSectorRecordTests(unittest.TestCase):
    def setUp(self):
        path = research/'homeland-terrain-sector-records.json'
        if not path.exists(): self.skipTest('Local terrain sector analysis unavailable')
        self.report = json.loads(path.read_text())
        self.root = json.loads((research/'homeland-runtime-terrain-root.json').read_text())

    def test_all_finest_sectors_and_next_lod_match_independent_source_heights(self):
        records = self.report['records']
        self.assertEqual(len(records), 320)
        self.assertEqual({(r['x'],r['z']) for r in records if r['level']==0}, {(x,z) for x in range(16) for z in range(16)})
        self.assertEqual({(r['x'],r['z']) for r in records if r['level']==1}, {(x,z) for x in range(8) for z in range(8)})
        self.assertEqual(self.report['independentHeightMismatches'], 0)
        self.assertTrue(all(r['independentHeightMismatches']==0 for r in records))
        coarse = next(r for r in records if r['level']==1 and r['x']==1 and r['z']==0)
        self.assertEqual(coarse['packetID'], 268435460)
        self.assertEqual(coarse['bounds']['center'][0], -320)

    def test_home_sector_maps_are_source_bound_and_never_reinterpreted_as_color(self):
        item = next(r for r in self.report['records'] if (r['level'],r['x'],r['z'])==(0,8,5))
        data = (research/item['recordFile']).read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), item['decodedSHA256'])
        self.assertEqual(len(item['maps']), 11)
        self.assertEqual(item['bounds']['center'][::2], [32,-160])
        for role, row in item['maps'].items():
            payload = data[row['offset']:row['offset']+row['bytes']]
            self.assertEqual(hashlib.sha256(payload).hexdigest(), row['sha256'])
            self.assertEqual(row['format'], self.root['descriptors'][role]['format'])
        self.assertEqual(item['maps']['index']['bytes'], 129*129*4)
        self.assertEqual(item['maps']['weight']['bytes'], 129*129)
        self.assertEqual(bytes.fromhex(item['opaqueTailHex']), data[item['interpretedBytes']:])

    def test_bad_coordinate_descriptor_and_truncated_map_rejected(self):
        item = next(r for r in self.report['records'] if r['level']==0 and r['x']==0 and r['z']==0)
        data = (research/item['recordFile']).read_bytes()
        bad = bytearray(data); struct.pack_into('<I', bad, 4, 16)
        with self.assertRaises(ValueError): module.record(bad, self.root)
        bad = bytearray(data); struct.pack_into('<H', bad, 36, 128)
        with self.assertRaises(ValueError): module.record(bad, self.root)
        with self.assertRaises(ValueError): module.record(data[:item['maps']['cone']['offset']+10], self.root)


if __name__ == '__main__': unittest.main()
