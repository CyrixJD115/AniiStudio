# Homeland environment export (read-only)

Two offline, read-only scripts that populate `~/Library/Application Support/AniimoAtlas/Environment/`,
the local cache the app's `HomelandSkySystem` and `HomelandTerrainSkirt` read from. Needs
`pip install UnityPy pillow` and the game volume mounted; `common.py` holds the game path and
the bundle index it reads from `Research/2026-10-28/patch-update`.

## export_env_textures.py
Exports 5 weather sky cloud-layer textures (Sunny, Sunny_02/Cloudy, Dawn, Dusk, Night), 2 night
extras (Moon, Stars) and 3 ground materials (Grass, Soil, Rock; diffuse+normal each) from the
installed game's Unity bundles. Writes PNGs + `env-export-report.json` into the Environment folder.

These sky textures are cloud-layer MASKS (mostly transparent, colored cloud shapes on black), not
flat sky images -- the game composites them over a proprietary procedural atmospheric-scattering
shader this project does not reproduce. `HomelandSkySystem.swift` instead draws its own simple
gradient sky dome (hand-authored colors, not extracted) and layers these real cloud textures on
top, tinted with the game's own real `_WeatherCloudShadowBright`/`Dark` colors (read from
`MI_Home_PhysicalSky.mat`).

## build_terrain_skirt.py
Stitches the 64 already-captured Homeland terrain heightmap tiles (cached at
`~/Library/.../Environment/World/terrain-*.u16le` from an earlier, unfinished session's capture;
re-verified here by checksum against `World/sources.json`) into one decimated mesh
(`terrain-skirt.json`, ~86x86 vertices). Computes a per-vertex grass/soil/rock blend weight from
local height and slope.

This is decorative only: it has no game-world coordinate calibration (that needs a live
`areaCenter` read this pass didn't have), so it's never used for placement, collision, or
alignment with the player's actual plot -- see the `scope` string the script writes into its own
output. `HomelandTerrainSkirt.swift` renders it as three separate plain-material geometry
elements split by dominant per-triangle blend weight (grass/soil/rock), not a smooth per-pixel
shader blend: a custom `sampler2D` shader-modifier argument was tried first and reliably failed
to render (solid magenta, SceneKit's invalid-material fallback) on this runtime.

## Re-running
Both scripts are idempotent; re-run either to refresh the cache after a game update. Neither
touches the game, the installed app, or anything outside `~/Library/Application Support/AniimoAtlas/Environment/`.
