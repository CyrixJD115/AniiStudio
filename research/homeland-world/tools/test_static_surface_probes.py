import json
from pathlib import Path
import struct
import unittest

research=Path(__file__).resolve().parent.parent/"Research/2026-10-23"


class StaticSurfaceProbeTests(unittest.TestCase):
    def setUp(self):
        path=research/"terrain-rock-pine-grass-qa/plant-static-surface-probes.json"
        if not path.exists():self.skipTest("Native triangle probe artifact unavailable")
        self.report=json.loads(path.read_text())

    def test_every_probe_retains_exact_original_plant_origin(self):
        source=json.loads((research/"homeland-vegetation-transforms.json").read_text())
        originals={f'{c["chunk"]}/{c["prototypeID"]}/{i["ordinal"]}':i["position"]
                   for c in source["chunks"] for i in c["instances"]}
        ids=[]
        for probe in self.report["probes"]:
            ids.append(probe["plant"])
            self.assertEqual(probe["sourcePosition"],originals[probe["plant"]])
            self.assertGreater(probe["heightTerrainResidualMetres"],1)
        self.assertEqual(len(ids),784)
        self.assertEqual(len(set(ids)),784)
        height=json.loads((research/"vegetation-ground-crosscheck.json").read_text())
        self.assertEqual(sum(g["aboveHeightTerrainOver1m"] for g in height["groups"]),len(ids))

    def test_surface_matches_are_original_rock_triangles_not_plant_self_hits(self):
        manifest=json.loads((research/"static-rock-models/manifest.json").read_text())
        names=set()
        for model in manifest["models"]:
            for renderer in model["renderers"]:
                data=(research/"static-rock-models"/renderer["file"]).read_bytes()
                size=struct.unpack_from("<I",data,12)[0]
                doc=json.loads(data[20:20+size])
                names.update(n["name"] for n in doc["nodes"] if "name" in n)
        matched=0
        for probe in self.report["probes"]:
            if "nearestStaticSurfaceResidualMetres" not in probe:continue
            self.assertGreater(probe["triangleHitCount"],0)
            self.assertIn(probe["surfaceNode"],names)
            if abs(probe["nearestStaticSurfaceResidualMetres"])<=.25:matched+=1
        self.assertEqual(matched,self.report["within25cmOfOriginalStaticSurface"])
        self.assertGreaterEqual(matched,650)


if __name__=="__main__":unittest.main()
