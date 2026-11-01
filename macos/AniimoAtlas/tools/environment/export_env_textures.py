"""Read-only export of weather-sky and ground-material textures from the installed
game client into the app's local Environment cache (same convention as the existing
grass/sunny-sky cache this session found already present)."""
import json, hashlib, io, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from common import asset_object, bundles, assets, lookup

OUT = Path.home() / "Library/Application Support/AniimoAtlas/Environment"
OUT.mkdir(parents=True, exist_ok=True)

def sha256(b): return hashlib.sha256(b).hexdigest()

def find_bundle_for(path):
    bid = assets.get(path.lower())
    return bundles[bid] if bid is not None else None

def export_png(unity_path, out_name):
    obj = asset_object(unity_path)
    img = obj.read().image.convert("RGBA")
    buf = io.BytesIO(); img.save(buf, format="PNG")
    data = buf.getvalue()
    (OUT / out_name).write_bytes(data)
    return {
        "name": obj.read().m_Name if hasattr(obj.read(), "m_Name") else Path(unity_path).stem,
        "file": out_name, "width": img.width, "height": img.height,
        "bundle": find_bundle_for(unity_path) or "", "bundleSHA256": "",
        "fileSHA256": sha256(data),
        "sourceAsset": unity_path,
    }

SKY = {
    "sunny": "assets/res/weather/pc/texture/sky/t_sky_imagecloud2d_sunny_c.tga",
    "sunny-alternate": "assets/res/weather/pc/texture/sky/t_sky_imagecloud2d_sunny_02_c.tga",
    "dawn": "assets/res/weather/pc/texture/sky/t_sky_imagecloud2d_dawn_c.tga",
    "dusk": "assets/res/weather/pc/texture/sky/t_sky_imagecloud2d_dusk_c.png",
    "night": "assets/res/weather/pc/texture/sky/t_sky_imagecloud2d_night_c.tga",
}
NIGHT_EXTRA = {
    "stars": "assets/res/weather/pc/texture/sky/t_sky_tilingstars_ca.tga",
    "moon": "assets/res/weather/pc/texture/sky/t_sky_moon_ca.tga",
}
GROUND = {
    "grass": {
        "diffuse": "assets/res_export/texture/common/environment/tilingcommontexture/terrain/grass/t_tiling_terrain_grass_001_ca.tga",
        "normal": "assets/res_export/texture/common/environment/tilingcommontexture/terrain/grass/t_tiling_terrain_grass_001_n.tga",
    },
    "soil": {
        "diffuse": "assets/res_export/texture/common/environment/tilingcommontexture/terrain/soil/t_tiling_terrain_soil_001_c.tga",
        "normal": "assets/res_export/texture/common/environment/tilingcommontexture/terrain/soil/t_tiling_terrain_soil_001_n.tga",
    },
    "rock": {
        "diffuse": "assets/res_export/texture/common/environment/tilingcommontexture/terrain/rock/t_tiling_terrain_rock_006_c.tga",
        "normal": "assets/res_export/texture/common/environment/tilingcommontexture/terrain/rock/t_tiling_terrain_rock_006_n.tga",
    },
}

report = {"version": 2, "source": "Installed Aniimo UnityFS bundles", "generatedBy": "export_env_textures.py",
          "sky": {}, "nightExtras": {}, "ground": {}, "failures": {}}

for name, path in SKY.items():
    try:
        report["sky"][name] = export_png(path, f"sky-{name}.png")
        print("sky", name, "OK")
    except Exception as e:
        report["failures"][name] = str(e); print("sky", name, "FAIL", e)

for name, path in NIGHT_EXTRA.items():
    try:
        report["nightExtras"][name] = export_png(path, f"night-{name}.png")
        print("night-extra", name, "OK")
    except Exception as e:
        report["failures"][name] = str(e); print("night-extra", name, "FAIL", e)

for mat, maps in GROUND.items():
    report["ground"][mat] = {}
    for kind, path in maps.items():
        try:
            report["ground"][mat][kind] = export_png(path, f"ground-{mat}-{kind}.png")
            print("ground", mat, kind, "OK")
        except Exception as e:
            report["failures"][f"{mat}-{kind}"] = str(e); print("ground", mat, kind, "FAIL", e)

(OUT / "env-export-report.json").write_text(json.dumps(report, indent=2))
print("done; failures:", len(report["failures"]))
