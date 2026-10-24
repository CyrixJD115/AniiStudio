import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import UnityPy

spec = importlib.util.spec_from_file_location("bundle_index", Path(__file__).with_name("index-unity-bundle-directories.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BundleIndexTests(unittest.TestCase):
    def test_real_directory_names_match_the_full_reference_loader(self):
        if not os.environ.get('ANII_GAME_ROOT'):self.skipTest('Set ANII_GAME_ROOT for installed bundle fixtures')
        root = Path(os.environ['ANII_GAME_ROOT'])/'Aniimo_Data/StreamingAssets/cvs/res/uab/win/DefaultPackage'
        if not root.exists():
            self.skipTest("Installed game resource directory unavailable")
        for pattern in ("mexp_level_extga_0_*.uab", "aexp_tcenv_tilect_terrain_grass_tga_0_*.uab"):
            with self.subTest(pattern=pattern):
                path = next(root.glob(pattern))
                actual = module.inspect(path)
                environment = UnityPy.load(str(path))
                expected = {name for bundle in environment.files.values() for name in bundle.files}
                self.assertEqual({entry["name"] for entry in actual["files"]}, expected)
                self.assertLess(actual["directoryBytesRead"], path.stat().st_size / 10)

    def test_non_bundle_and_truncated_signature_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.uab"
            for data in (b"NotUnity\0", b"UnityFS\0\0\0"):
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    module.inspect(path)


if __name__ == "__main__":
    unittest.main()
