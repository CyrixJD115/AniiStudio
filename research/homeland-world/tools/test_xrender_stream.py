import importlib.util
import os
from pathlib import Path
import struct
import unittest
import zstandard

spec = importlib.util.spec_from_file_location("xrender_stream", Path(__file__).with_name("read-xrender-stream.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class XRenderStreamTests(unittest.TestCase):
    def envelope(self, content):
        compressed = zstandard.ZstdCompressor().compress(content)
        return bytes([255, 1]) + struct.pack("<II", len(compressed), len(content)) + compressed

    def test_single_record_roundtrip_and_truncation(self):
        data = self.envelope(b"static resource bytes")
        self.assertEqual(module.decode(data)[0]["bytes"], b"static resource bytes")
        for trim in (1, 5, len(data) - 1):
            with self.assertRaises((ValueError, zstandard.ZstdError)):
                module.decode(data[:-trim])

    def test_declared_decompression_limit_is_enforced(self):
        data = bytearray(self.envelope(b"test"))
        struct.pack_into("<I", data, 6, module.LIMIT + 1)
        with self.assertRaises(ValueError):
            module.decode(data)

    def test_overlapping_directory_entries_are_rejected(self):
        body = self.envelope(b"test")[1:]
        data = bytes([255, 0]) + struct.pack("<I", 24)
        data += struct.pack("<III", 1, 30, len(body)) + struct.pack("<III", 2, 30, len(body)) + body
        with self.assertRaises(ValueError):
            module.decode(data)

    def test_frame_declared_size_cannot_override_envelope_bound(self):
        data = bytearray(self.envelope(b"longer than four bytes"))
        struct.pack_into("<I", data, 6, 4)
        with self.assertRaises(ValueError):
            module.decode(data)

    def test_actual_homeland_storage_and_chunk_wrappers_validate(self):
        if not os.environ.get('ANII_GAME_ROOT'):self.skipTest('Set ANII_GAME_ROOT for installed stream fixtures')
        root = Path(os.environ['ANII_GAME_ROOT'])/'AssetsExtra/raw/xrenderPC/RuntimeLevel_FB_Home_01'
        if not root.exists():
            self.skipTest("Installed static stream data unavailable")
        for name, count in (("Vegetation/Storage.bin", 1), ("Vegetation/Chunk/0_0.pack", 8),
                            ("XBatch/XBatchStorage.bin", 1), ("XBatch/XBatch.pack", 220),
                            ("XTerrain/TerrainRootAsset/TerrainRootAsset.bin", 1),
                            ("XTerrain/TerrainBinaryPack/0.pack", 64), ("XTerrain/TerrainBinaryPack/256.pack", 64)):
            with self.subTest(name=name):
                self.assertEqual(len(module.decode((root / name).read_bytes())), count)


if __name__ == "__main__":
    unittest.main()
