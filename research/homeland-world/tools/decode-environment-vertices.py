#!/usr/bin/env python3
"""Original EV_HomeGrass compressed-vertex formulas, recovered from its DXBC.

Evidence: grass-p4-s0-v7.asm instructions23-55; v8 confirms position/UV.
Returns Unity source coordinates. Converting basis is an exporter's responsibility.
"""
import math


def decode(position, normal, uv):
    if len(position) != 4 or len(normal) < 1 or len(uv) < 2:
        raise ValueError("Unexpected compressed vertex dimensions")
    if any(not isinstance(v, int) or not 0 <= v <= 65535 for v in (*position, *normal, *uv)):
        raise ValueError("Expected UInt16 source attributes")
    extent = 1 << (3 + ((position[3] >> 1) & 7))
    xyz = [v / 65535 * (2*extent) - extent for v in position[:3]]
    nx = ((position[3] >> 4) & 65535) / 4095 * 2 - 1
    ny = ((normal[0] >> 4) & 65535) / 4095 * 2 - 1
    nz = 1-abs(nx)-abs(ny)
    fold = max(-nz, 0)
    nx += -fold if nx >= 0 else fold
    ny += -fold if ny >= 0 else fold
    length = math.sqrt(nx*nx+ny*ny+nz*nz)
    if length < 1e-9:
        raise ValueError("Degenerate packed normal")
    return xyz, [nx/length, ny/length, nz/length], [v * 0.000488288701 - 16 for v in uv[:2]]
