# Creature model export (read-only)
Exports installed game `P_Parmon_<id>` prefabs (skinned meshes, skeleton, base PBR textures, bind pose) to GLB. Needs `pip install UnityPy pillow` and the game volume mounted; `common.py` holds the game path and the bundle index it reads from `Research/2026-10-28/patch-update`.
Run: `OUT=<dir> python batch.py` (ids in `ids.txt`, derived from `selection.json`).
Not ported: Unity shader effects, particles, animation clips (idle clips use Unity's quantized format, not yet decoded). Not exported: prefabs 1061101, 1061102, 1061301, 1061302 (variant prefabs with no resolvable root); the app falls back to the base form model.
Form to prefab: form ids ending `00` use the first 5 digits, others the first 7.
