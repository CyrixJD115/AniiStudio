import hashlib
import json
from pathlib import Path
import unittest

research = Path(__file__).resolve().parent.parent/'Research/2026-10-23'


class CapturedWorldAlignmentTests(unittest.TestCase):
    def test_native_world_preserves_every_captured_matrix_and_exact_origin(self):
        source = research/'residential-world-content/residential-content.json'
        rendered = research/'captured-home-world-qa/rendered-world-summary.json'
        if not source.exists() or not rendered.exists(): self.skipTest('Local native integration artifacts unavailable')
        capture = json.loads(source.read_text()); world = json.loads(rendered.read_text())
        self.assertEqual(capture['captureSHA256'], world['captureSHA256'])
        self.assertEqual((capture['originX'], capture['originZ']), (world['originX'], world['originZ']))
        expected = {p['id']: p['nativeTransform'] for p in capture['placements']}
        actual = {p['id']: p['nativeTransform'] for p in world['capturedInstances']}
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 3118)
        self.assertEqual(capture['totalCapturedAreaRecords'], len(actual)+capture['missingModels'])
        self.assertEqual(capture['missingModels'], 1)
        self.assertEqual(hashlib.sha256((source.parent/'residential-content.scn').read_bytes()).hexdigest(), capture['sceneSHA256'])
        self.assertEqual(world['terrainTiles'], 64)
        self.assertEqual(world['rockInstances'], 533)
        self.assertEqual(world['pineInstances'], 1528)
        self.assertEqual(world['grassInstances'], 1735)
        self.assertEqual(len(world['waterInstances']), 13)


if __name__ == '__main__': unittest.main()
