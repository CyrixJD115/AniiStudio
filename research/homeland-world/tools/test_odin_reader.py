import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("odin_reader", Path(__file__).with_name("read-odin-binary.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class OdinReaderTests(unittest.TestCase):
    def test_unknown_type_is_rejected_without_instantiating_it(self):
        # Unnamed struct, type reference37 never defined in this stream.
        with self.assertRaises(ValueError):
            module.Reader(bytes([4, 48]) + struct.pack("<i", 37)).sequence()

    def test_oversized_primitive_array_and_negative_string_are_rejected(self):
        for data in (bytes([8]) + struct.pack("<ii", 1_000_001, 4),
                     bytes([40, 0]) + struct.pack("<i", -1)):
            with self.assertRaises(ValueError):
                module.Reader(data).sequence()

    def test_unclosed_or_truncated_container_is_rejected(self):
        # Unnamed struct without metadata, then one complete int, missing close.
        data = bytes([4, 46, 24]) + struct.pack("<i", 100)
        with self.assertRaises(ValueError):
            module.Reader(data).sequence()
        for count in range(1, 5):
            with self.assertRaises(ValueError):
                module.Reader(bytes([24]) + b"\0" * (count - 1)).sequence()

    def test_array_length_disagreement_is_not_silently_accepted(self):
        data = bytes([6]) + struct.pack("<q", 2) + bytes([24]) + struct.pack("<i", 5) + bytes([7])
        with self.assertRaises(ValueError):
            module.Reader(data).sequence()

    def test_real_static_vegetation_payload_consumes_exactly_and_preserves_unity_references(self):
        path = Path.home() / "Library/Application Support/AniimoAtlas/Environment/World/vegetation-odin.bin"
        if not path.exists():
            self.skipTest("Local game static vegetation data unavailable")
        data = path.read_bytes()
        reader = module.Reader(data)
        values = reader.sequence()
        self.assertEqual(reader.pos, len(data))
        self.assertEqual(values[0]["name"], "m_ProtoType")
        prototypes = values[0]["children"][0]["children"]
        self.assertEqual(len(prototypes), 21)
        for prototype in prototypes:
            fields = {item.get("name"): item for item in prototype["children"]}
            self.assertTrue(fields["m_PrefabName"]["value"].startswith("EPrefab_"))
            self.assertIn(fields["m_Prefab"]["externalReference"], range(20))


if __name__ == "__main__":
    unittest.main()
