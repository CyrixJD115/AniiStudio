import importlib.util
import os
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("xbatch_world", Path(__file__).with_name("read-xbatch-world.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(os.environ['ANII_GAME_ROOT'])/'AssetsExtra/raw/xrenderPC/RuntimeLevel_FB_Home_01/XBatch' if os.environ.get('ANII_GAME_ROOT') else None


class XBatchWorldTests(unittest.TestCase):
    def fixture(self, identity=7, x=1):
        draws = struct.pack("<4I",12,0,0,1)
        instance = struct.pack("<11fI",x,2,3,1,0,0,0,1,1,2,3,identity)
        return draws + struct.pack("<I",48) + instance + bytes(24)

    def test_source_transform_fixture_and_culling_copy_dedup(self):
        a = module.packet(self.fixture())
        self.assertEqual(a["instances"][0]["position"],[1,2,3])
        self.assertEqual(a["instances"][0]["scale"],[1,2,3])
        result=module.unique_instances({10:a,20:module.packet(self.fixture())},1)
        self.assertEqual(len(result),1)
        self.assertEqual(result[0]["packetCopies"],[10,20])
        # Distinct IDs at coincident poses remain separate objects.
        self.assertEqual(len(module.unique_instances({10:a,20:module.packet(self.fixture(identity=9))},1)),2)

    def test_conflicting_copies_and_unknown_prototypes_rejected(self):
        a,b=module.packet(self.fixture()),module.packet(self.fixture(x=2))
        with self.assertRaises(ValueError):module.unique_instances({10:a,20:b},1)
        with self.assertRaises(ValueError):module.unique_instances({10:a},0)

    def test_corrupt_affine_data_truncation_and_draw_ranges_rejected(self):
        source=self.fixture()
        cases=[source[:-1],source+b"\0"]
        for offset,value in [(0,13),(12,2),(32,0),(36,2),(52,0)]:
            data=bytearray(source)
            struct.pack_into("<I" if offset in (0,12) else "<f",data,offset,value)
            cases.append(bytes(data))
        for data in cases:
            with self.assertRaises(ValueError):module.packet(data)

    def test_independent_resource_pointer_disagreement_rejected(self):
        table={"materials":[{"path":"Assets/Material.mat"}],"meshes":[{"path":"Assets/Missing.asset"}]}
        refs={"externalFiles":["archive:/cab-a/cab-a"],"data":{"m_Reference":[
            {"m_FileID":1,"m_PathID":42},{"m_FileID":1,"m_PathID":77}]}}
        index={"Assets/Material.mat":{"cab":"CAB-A","pathID":42}}
        self.assertEqual(module.bind_resources(table,refs,index),(1,["Assets/Missing.asset"]))
        # A newer index entry sharing a path must not override the explicit CAB/pointer.
        index["Assets/Material.mat"]=[{"cab":"CAB-A","pathID":42},{"cab":"CAB-OTHER","pathID":43}]
        self.assertEqual(module.bind_resources(table,refs,index),(1,["Assets/Missing.asset"]))
        index["Assets/Material.mat"]={"cab":"CAB-A","pathID":43}
        with self.assertRaises(ValueError):module.bind_resources(table,refs,index)

    def test_real_storage_all_tables_consumed_and_linked(self):
        if root is None or not root.exists():self.skipTest("Set ANII_GAME_ROOT for installed static resources")
        decoded=module.stream.decode((root/"XBatchStorage.bin").read_bytes())[0]["bytes"]
        table=module.storage(decoded)
        self.assertEqual(table["bytesConsumed"],len(decoded))
        self.assertEqual([len(table[k]) for k in ("prototypes","renderers","materialIndices","meshes","materials","packetIDs")],
                         [139,401,511,398,114,220])
        for trim in (1,4,20):
            with self.assertRaises(ValueError):module.storage(decoded[:-trim])

    def test_all_real_packets_partition_and_deduplicate_exactly(self):
        if root is None or not root.exists():self.skipTest("Set ANII_GAME_ROOT for installed static resources")
        packets={r["id"]:module.packet(r["bytes"]) for r in module.stream.decode((root/"XBatch.pack").read_bytes())}
        self.assertEqual(len(packets),220)
        self.assertEqual(sum(len(p["instances"]) for p in packets.values()),4249)
        instances=module.unique_instances(packets,139)
        self.assertEqual(len(instances),1152)
        self.assertEqual([i["sourceInstanceID"] for i in instances],list(range(1152)))
        self.assertEqual(sum(len(i["packetCopies"]) for i in instances),4249)


if __name__ == "__main__":unittest.main()
