"""Offline, read-only: stitch the already-captured Homeland terrain heightmap tiles
(cached locally from a prior extraction; re-verified by checksum here) into a single
decorative, decimated terrain mesh for the Homeland builder's 3D backdrop.

This is NOT the calibrated, exactly-placed terrain (that needs a live area-center
read this pass does not have). It is a generic "real terrain shape, real textures"
decorative skirt surrounding the flat, precisely-buildable plot. Labelled as such
in the manifest it writes.
"""
import json, hashlib, struct, math, sys
from pathlib import Path

ROOT = Path.home() / "Library/Application Support/AniimoAtlas/Environment/World"
OUT = Path.home() / "Library/Application Support/AniimoAtlas/Environment"

def sha256(b): return hashlib.sha256(b).hexdigest()

def checked(name, expected):
    data = (ROOT / name).read_bytes()
    got = sha256(data)
    assert got == expected, f"checksum mismatch for {name}: {got} != {expected}"
    return data

def main():
    src = json.loads((ROOT / "sources.json").read_text())
    tiles = {(t["x"], t["z"]): t for t in src["terrain"]}
    assert len(tiles) == 64, f"expected 64 terrain tiles, found {len(tiles)}"
    for t in tiles.values():
        assert t["resolution"] == 257
        assert t["scale"] == {"x": 0.5, "y": 600.0, "z": 0.5}

    # Decode every tile's 257x257 heightfield (verified against its own checksum).
    heights = {}
    holes = {}
    for key, t in tiles.items():
        raw = checked(t["file"], t["fileSHA256"])
        assert len(raw) == 257 * 257 * 2
        heights[key] = struct.unpack("<" + "H" * (257 * 257), raw)
        hraw = checked(t["holesFile"], t["holesSHA256"])
        holes[key] = hraw if hraw else None

    scale_y = 600.0
    # Stitch into one logical (8*256+1) x (8*256+1) sample grid, taking each tile's
    # first 256x256 samples (avoiding duplicate shared edge columns/rows between
    # adjacent tiles, standard Unity terrain tiling convention) plus one final edge.
    N = 257

    def sample(gx, gz):
        gx = min(2048, max(0, gx)); gz = min(2048, max(0, gz))
        tx, tz = min(7, gx // 256), min(7, gz // 256)
        lx, lz = gx - tx * 256, gz - tz * 256
        h = heights[(tx, tz)]
        return h[lz * N + lx]

    # Decimate to a manageable mesh: sample every STRIDE grid units.
    STRIDE = 24
    SIZE = 2048 // STRIDE + 1  # ~86
    raw_grid = [[sample(gx * STRIDE, gz * STRIDE) for gx in range(SIZE)] for gz in range(SIZE)]

    all_raw = [v for row in raw_grid for v in row if v > 0]
    rmin, rmax = min(all_raw), max(all_raw)

    def world_height(raw):
        if raw <= 0: return None  # hole / no data
        return raw / 65535.0 * scale_y

    hmin = world_height(rmin); hmax = world_height(rmax)
    relief = max(0.01, hmax - hmin)

    # World-space spacing between decimated samples (arbitrary decorative scale:
    # 0.5 game units per raw sample * STRIDE, matching the tile's own x/z scale).
    spacing = 0.5 * STRIDE

    verts = []
    normed_h = [[None] * SIZE for _ in range(SIZE)]
    for gz in range(SIZE):
        for gx in range(SIZE):
            raw = raw_grid[gz][gx]
            wh = world_height(raw)
            # Normalize relief to a tasteful decorative amplitude (not to-scale,
            # not calibrated placement -- see module docstring).
            normed = 0.0 if wh is None else (wh - hmin) / relief
            normed_h[gz][gx] = normed
            y = normed * 7.5  # max ~7.5 units of decorative relief
            x = (gx - SIZE / 2) * spacing
            z = (gz - SIZE / 2) * spacing
            verts.append((x, y, z))

    # Vertex normals via central differences, and a grass/soil/rock blend weight
    # from local slope (steeper -> more rock) and height band (lower, flat -> soil).
    def idx(gx, gz): return gz * SIZE + gx
    normals = [None] * len(verts)
    blend = [None] * len(verts)  # (grass, soil, rock)
    for gz in range(SIZE):
        for gx in range(SIZE):
            l = verts[idx(max(0, gx - 1), gz)]
            r = verts[idx(min(SIZE - 1, gx + 1), gz)]
            d = verts[idx(gx, max(0, gz - 1))]
            u = verts[idx(gx, min(SIZE - 1, gz + 1))]
            dx = (r[0] - l[0], r[1] - l[1], r[2] - l[2])
            dz = (u[0] - d[0], u[1] - d[1], u[2] - d[2])
            nx = dx[1] * dz[2] - dx[2] * dz[1]
            ny = dx[2] * dz[0] - dx[0] * dz[2]
            nz = dx[0] * dz[1] - dx[1] * dz[0]
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            nx, ny, nz = nx / ln, ny / ln, nz / ln
            if ny < 0: nx, ny, nz = -nx, -ny, -nz
            normals[idx(gx, gz)] = (nx, ny, nz)
            slope = 1.0 - max(0.0, min(1.0, ny))  # 0 flat, 1 vertical
            h = normed_h[gz][gx]
            rock = max(0.0, min(1.0, (slope - 0.18) / 0.5))
            soil = max(0.0, min(1.0, 1.0 - h * 1.6)) * (1.0 - rock) * 0.6
            grass = max(0.0, 1.0 - rock - soil)
            blend[idx(gx, gz)] = (grass, soil, rock)

    indices = []
    for gz in range(SIZE - 1):
        for gx in range(SIZE - 1):
            a, b, c, d = idx(gx, gz), idx(gx + 1, gz), idx(gx, gz + 1), idx(gx + 1, gz + 1)
            indices += [a, c, b, b, c, d]

    out = {
        "schema": "aniimo-terrain-skirt-v1",
        "scope": "Decorative backdrop only: real captured Homeland terrain shape and "
                 "real game ground textures, decimated and re-scaled for visual relief. "
                 "NOT calibrated to any specific plot's exact world coordinates; never "
                 "used for placement, collision, or precise alignment. The buildable "
                 "plot itself stays an exact flat plane, unaffected by this mesh.",
        "gridSize": SIZE,
        "spacing": spacing,
        "sourceTileCount": len(tiles),
        "sourceChecksums": {t["file"]: t["fileSHA256"] for t in tiles.values()},
        "vertices": [c for v in verts for c in v],
        "normals": [c for n in normals for c in n],
        "blendWeights": [c for b in blend for c in b],
        "indices": indices,
    }
    (OUT / "terrain-skirt.json").write_text(json.dumps(out))
    print(f"terrain skirt: {SIZE}x{SIZE} verts ({len(verts)}), {len(indices)//3} tris, "
          f"relief {relief:.1f} raw units -> written to {OUT/'terrain-skirt.json'}")

if __name__ == "__main__":
    main()
