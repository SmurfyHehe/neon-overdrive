"""Engine bays as kit parts (engine bays B3, notes/engine-bays-better-2026-10-13.md
sections 2c, 2d and 5): what sits under a lid, built the same way the kits
build lamps and brakes, and written to its own file by `build_car.py --bay`.

    python tools/car_pipeline/build_car.py p1_coupe --bay      # -> assets/cars/p1_coupe/bay.glb + bay.json

Why a file of its own: the driving body (body.glb, Blender-bevelled) never
carries the bay, and the game loads the bay only while a lid is up
(CarAssembler.build_bay through CarDetail). This writer runs on the Python
backend, so a bay rebuilds in the cloud without Blender; castings and hoses
want no bevel anyway.

Rules the parts follow (section 4, so tools/car_pipeline/fit_check.py and
tests/car/part_fit.gd stay green): the tallest item sits at least 40 mm under
the hood's underside (checked at 25), 20 mm inside the fender's inner wall
(checked at 10), parts keep 5 mm from each other unless the pair is in
TOUCHING (a hose on its radiator, the belt on its pulleys), nothing within
60 mm of the hinge line. `ctx.hood_under(x, z)` and `ctx.wall_x(y, z)` read
the real body, so a part placed through them clears by construction.

Materials: `cast` (dark engine castings), `alloy` (brushed covers and
plenums), `steel`, `chrome` (caps and bright bits), `plastic`, `rubber`,
`under_paint` (the dark tub), `glow_lens` (the under-hood bulb, unshaded so it
costs no light). Three draw calls in the game: body (under_paint), trim, glow.

The look rule (section 2c): one shape you know from the nose in one second.
The coupe's is the long inline-six cover with six coil packs and the plenum's
six runners down its side, radiator with one big fan ahead of it, strut tops
either side, nothing hiding any of it.
"""
import math

import numpy as np

import parts as P
from kits import cyl

# bay part pairs that are built touching (hose on its tank, belt on its
# pulleys): the fit checkers skip their overlap; both checkers list the same
TOUCHING = {
    ('bay_hoses', 'bay_radiator'), ('bay_hoses', 'bay_shroud'), ('bay_hoses', 'engine'),
    ('bay_belt', 'engine'), ('bay_airbox', 'engine'),
    ('bay_cables', 'bay_battery'), ('bay_cables', 'engine'),
    ('bay_shroud', 'bay_radiator'),
}

HOOD_CLEAR = 0.040     # tallest fixed item this far under the hood (checker: 25 mm)
WALL_CLEAR = 0.020     # this far inside the fender's inner wall (checker: 10 mm)
HINGE_CLEAR = 0.060    # nothing within this of the hinge line
ARCH_R = 0.345         # the front wheel arch's radius round the hub, where the tub wall has its foot
LINER_X = 0.608        # the arch liner's flat inner face (its min x on the coupe)
LINER_TOP = 0.665      # how high the liner reaches


def _seg(part, pts, r, n, mat, caps=(True, True)):
    """A tube along a polyline (a hose, a pipe, a cable): one cylinder per leg,
    a short cylinder across each knee so the bend reads closed."""
    pts = [np.asarray(p, float) for p in pts]
    last = len(pts) - 2
    for i in range(len(pts) - 1):
        cyl(part, pts[i], pts[i + 1], r, n, mat, caps=(caps[0] if i == 0 else False, caps[1] if i == last else False))
    for i in range(1, len(pts) - 1):
        d = (pts[i + 1] - pts[i - 1])
        d = d / max(np.linalg.norm(d), 1e-9) * r * 0.6
        cyl(part, pts[i] - d, pts[i] + d, r * 0.98, n, mat, caps=(True, True))


def _box(part, c, size, mat, yaw=0.0):
    B = P.yaw_basis(yaw) if yaw else np.eye(3)
    P.obox(part, c, size, B, mat)


def _ring(part, c, axis_z, r_out, r_in, depth, n, mat):
    """A flat ring (a fan shroud mouth, a pulley rim) in the x-y plane at z=c[2]."""
    cz = np.asarray(c, float)
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        o0 = cz + np.array([r_out * math.cos(a0), r_out * math.sin(a0), 0])
        o1 = cz + np.array([r_out * math.cos(a1), r_out * math.sin(a1), 0])
        i0 = cz + np.array([r_in * math.cos(a0), r_in * math.sin(a0), 0])
        i1 = cz + np.array([r_in * math.cos(a1), r_in * math.sin(a1), 0])
        d = np.array([0, 0, depth])
        front = -1.0 if axis_z < 0 else 1.0
        # front face, back face, outer rim, inner rim
        part.add(P.facing([(o0, o1, i1, i0)], np.array([0, 0, front]))[0], mat)
        part.add(P.facing([(o0 + d, o1 + d, i1 + d, i0 + d)], np.array([0, 0, -front]))[0], mat)
        part.add(P.facing([(o0, o1, o1 + d, o0 + d)], (o0 + o1) / 2 - cz)[0], mat)
        part.add(P.facing([(i0, i1, i1 + d, i0 + d)], cz - (i0 + i1) / 2)[0], mat)


def _fan(part, c, r, blades, hub_r, mat_blade, mat_hub):
    """A cooling fan in the x-y plane: a hub cylinder and flat pitched blades."""
    c = np.asarray(c, float)
    cyl(part, c - np.array([0, 0, 0.02]), c + np.array([0, 0, 0.02]), hub_r, 8, mat_hub)
    for k in range(blades):
        a = 2 * math.pi * k / blades
        ca, sa = math.cos(a), math.sin(a)
        rad = np.array([ca, sa, 0.0])
        tan = np.array([-sa, ca, 0.0])
        root_w, tip_w, pitch = 0.035, 0.055, 0.012
        p0 = c + rad * (hub_r + 0.005) - tan * root_w + np.array([0, 0, pitch])
        p1 = c + rad * (hub_r + 0.005) + tan * root_w - np.array([0, 0, pitch])
        p2 = c + rad * r + tan * tip_w - np.array([0, 0, pitch])
        p3 = c + rad * r - tan * tip_w + np.array([0, 0, pitch])
        part.add(P.facing([(p0, p1, p2, p3)], np.array([0, 0, -1.0]))[0], mat_blade)
        part.add(P.facing([(p0, p1, p2, p3)], np.array([0, 0, 1.0]))[0], mat_blade)


def _pulley(part, c, r, w, n, mat):
    c = np.asarray(c, float)
    cyl(part, c - np.array([0, 0, w / 2]), c + np.array([0, 0, w / 2]), r, n, mat)
    cyl(part, c - np.array([0, 0, w / 2 + 0.004]), c + np.array([0, 0, w / 2 + 0.004]), r * 0.3, 6, 'steel')


def _belt(part, centres_r, z, w, mat):
    """A flat belt round pulleys given as (centre xy, radius), in order, as
    straight bands between neighbours (the wrap round each pulley is the
    pulley's own rim). Thin boxes, so the belt reads from above."""
    pts = []
    n = len(centres_r)
    for i in range(n):
        (c0, r0), (c1, r1) = centres_r[i], centres_r[(i + 1) % n]
        c0, c1 = np.asarray(c0, float), np.asarray(c1, float)
        d = c1 - c0
        L = np.linalg.norm(d)
        d = d / L
        nrm = np.array([-d[1], d[0]])
        # the outer tangent: offset both ends by their radius along the outer normal
        a = c0 + nrm * r0
        b = c1 + nrm * r1
        mid = (a + b) / 2
        ang = math.degrees(math.atan2(d[0], d[1]))
        c3 = np.array([mid[0], mid[1], z])
        B = np.column_stack([np.array([d[0], d[1], 0]), np.array([nrm[0], nrm[1], 0]), np.array([0, 0, 1.0])])
        P.obox(part, c3, (float(np.linalg.norm(b - a)), 0.006, w), B, mat)


def coupe_bay(ctx):
    """P1 coupe, inline six (section 2c row `inline6`, the showpiece)."""
    part = ctx.part
    hood = ctx.hood_under
    A = ctx.anchors
    z_eng = A['bay_engine'][2]            # -1.09: the block's centre
    z_rad = A['bay_radiator'][2] + 0.07   # -1.95: back from the anchor, under a higher stretch of nose
    hinge_z = A['hinge_hood'][2]          # -0.71
    firewall_z = hinge_z - HINGE_CLEAR    # -0.77: the firewall's front face
    nose_z = z_rad - 0.10                 # the radiator support
    FLOOR = 0.30
    hub_r = A['hub_fr']

    def tub_x(z):
        """The inner fender's face at station z: 30 mm inside the hood's edge,
        and inside the arch liner's flat over the front wheel."""
        x = ctx.hood_edge(z) - 0.030
        if abs(z - hub_r[2]) < ARCH_R + 0.05:
            x = min(x, LINER_X - 0.025)
        return x
    TUB_X = tub_x(firewall_z - 0.10)      # the widest the tub gets, at the back
    IN_X = min(tub_x(zz) for zz in np.linspace(nose_z, firewall_z, 20)) - 0.015   # the widest a part may reach anywhere

    # ---- the tub: dark inner fenders, firewall, radiator support (under_paint, body surface)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        w = part('bay_wall_' + nm, bevel=0)
        zs = np.linspace(nose_z + 0.075, firewall_z - 0.012, 13)
        # the top runs a step under the hood; over the arch it stops at the
        # liner's height, since there is no fender inner wall above the liner
        top = [min(hood(sx * (tub_x(zz) - 0.002), zz) - 0.035, LINER_TOP - 0.010 if abs(zz - hub_r[2]) < ARCH_R + 0.05 else 9.0) for zz in zs]
        # the wall's foot rides over the front wheel arch (the arch liner is the
        # wall there): the arch circle round the hub, a step above the liner
        hub = A['hub_f' + ('r' if sx > 0 else 'l')]
        foot = [max(FLOOR, hub[1] + math.sqrt(max(0.0, ARCH_R ** 2 - (zz - hub[2]) ** 2)) + 0.015) if abs(zz - hub[2]) < ARCH_R else FLOOR for zz in zs]
        foot = [min(f, t - 0.002) for f, t in zip(foot, top)]   # over the hub the liner is all the wall there is
        xs = [sx * tub_x(zz) for zz in zs]
        for i in range(len(zs) - 1):
            a = np.array([xs[i], foot[i], zs[i]]); b = np.array([xs[i + 1], foot[i + 1], zs[i + 1]])
            c = np.array([xs[i + 1], top[i + 1], zs[i + 1]]); d = np.array([xs[i], top[i], zs[i]])
            o = np.array([sx * 0.010, 0, 0])
            w.add(P.facing([(a, b, c, d)], np.array([-sx, 0.0, 0.0]))[0], 'under_paint')
            w.add(P.facing([(a + o, b + o, c + o, d + o)], np.array([sx, 0.0, 0.0]))[0], 'under_paint')
            w.add(P.facing([(d, c, c + o, d + o)], np.array([0, 1.0, 0]))[0], 'under_paint')
    fw = part('bay_firewall', bevel=0)
    fw_top = hood(0.0, firewall_z) - 0.045
    _box(fw, (0.0, (FLOOR + fw_top) / 2, firewall_z + 0.005), (2 * (tub_x(firewall_z - 0.01) - 0.012), fw_top - FLOOR, 0.010), 'under_paint')
    # the floor: the subframe tray between the walls, 2 mm under the sump, so
    # the bay is not a black hole under the engine (dark steel, not body paint)
    fl = part('bay_floor', bevel=0)
    fzs = np.linspace(nose_z + 0.075, firewall_z - 0.012, 9)
    for i in range(len(fzs) - 1):
        xa, xb = tub_x(fzs[i]) - 0.014, tub_x(fzs[i + 1]) - 0.014
        a = np.array([-xa, FLOOR - 0.002, fzs[i]]); b = np.array([xa, FLOOR - 0.002, fzs[i]])
        c = np.array([xb, FLOOR - 0.002, fzs[i + 1]]); d = np.array([-xb, FLOOR - 0.002, fzs[i + 1]])
        fl.add(P.facing([(a, b, c, d)], np.array([0.0, 1.0, 0.0]))[0], 'steel')
    rs = part('bay_rad_support', bevel=0)
    rs_z = nose_z + 0.02
    rs_top = min(hood(x, rs_z) for x in np.linspace(-0.40, 0.40, 9)) - 0.045
    rs_mid = FLOOR + (rs_top - FLOOR) * 0.62

    def fit_w(y_top, w):
        """The widest half width at which a panel top at y_top still clears the
        nose's roof (which drops toward the corners) by HOOD_CLEAR."""
        while w > 0.2 and min(hood(x, rs_z + dz) for x in np.linspace(-w, w, 15) for dz in (-0.006, 0.0, 0.036)) - HOOD_CLEAR - 0.005 < y_top:
            w -= 0.005
        return w
    # the nose tapers: a wide low panel and a narrower one above it, each as wide as its top allows
    lo_w = fit_w(rs_mid, min(tub_x(rs_z), ctx.wall_x(rs_mid, rs_z) - 0.03) - 0.012)
    hi_w = fit_w(rs_top, ctx.wall_x(rs_top, rs_z) - 0.035)
    _box(rs, (0.0, (FLOOR + rs_mid) / 2, rs_z), (2 * lo_w, rs_mid - FLOOR, 0.010), 'under_paint')
    _box(rs, (0.0, (rs_mid + rs_top) / 2, rs_z), (2 * hi_w, rs_top - rs_mid, 0.010), 'under_paint')
    _box(rs, (0.0, FLOOR + 0.01, rs_z + 0.015), (2 * lo_w, 0.02, 0.04), 'under_paint')      # lower crossmember
    _box(rs, (0.0, rs_top - 0.01, rs_z + 0.015), (2 * hi_w, 0.02, 0.04), 'under_paint')     # upper crossmember
    _box(rs, (0.0, rs_top - 0.040, rs_z + 0.015), (0.08, 0.04, 0.04), 'steel')               # the hood latch on it
    cyl(rs, (0.0, rs_top - 0.02, rs_z + 0.015), (0.0, rs_top + 0.010, rs_z + 0.015), 0.008, 6, 'steel')   # the striker

    # ---- the engine: block, head, the long alloy cover with six coil packs, plenum, manifold
    en = part('engine', bevel=0)
    z1 = firewall_z - 0.030               # the back of the block, 30 mm off the firewall
    z0 = z1 - 0.70                        # a straight six is long: -1.50 .. -0.80
    zc = (z0 + z1) / 2
    L = z1 - z0
    _box(en, (0.0, 0.41, zc), (0.30, 0.22, L), 'cast')                  # the block
    _box(en, (0.0, 0.545, zc), (0.26, 0.05, L - 0.02), 'cast')          # the head
    # the cam cover's lid: under the lowest hood over its length, with HOOD_CLEAR and the coil packs on top
    cover_top = min(hood(0.0, zz) for zz in np.linspace(z0, z1, 8)) - HOOD_CLEAR - 0.044
    cover_y0 = 0.57
    _box(en, (0.0, (cover_y0 + cover_top) / 2, zc), (0.24, cover_top - cover_y0, L - 0.04), 'alloy')
    _box(en, (0.0, cover_top + 0.006, zc), (0.19, 0.012, L - 0.08), 'alloy')       # the raised crown
    for k in range(6):                                                   # six coil packs along the crown
        zz = z0 + 0.07 + k * (L - 0.14) / 5
        _box(en, (0.02, cover_top + 0.012 + 0.014, zz), (0.034, 0.028, 0.040), 'plastic')
    cyl(en, (-0.06, cover_top + 0.012, z0 + 0.10), (-0.06, cover_top + 0.040, z0 + 0.10), 0.028, 8, 'chrome')  # oil cap
    # plenum down the right side: a log with six runners curving into the head
    px, py = 0.235, 0.545
    cyl(en, (px, py, z0 + 0.02), (px, py, z1 - 0.06), 0.052, 10, 'alloy')
    for k in range(6):
        zz = z0 + 0.07 + k * (L - 0.14) / 5
        cyl(en, (px - 0.01, py - 0.02, zz), (0.145, 0.50, zz), 0.021, 7, 'alloy', caps=(False, False))
    cyl(en, (px, py, z0 + 0.02), (px, py, z0 - 0.045), 0.040, 10, 'alloy')       # the throttle body
    # exhaust manifold down the left: a cast log with a heat shield over it
    mx, my = -0.235, 0.455
    cyl(en, (mx, my, z0 + 0.04), (mx, my, z1 - 0.08), 0.040, 8, 'cast')
    for k in range(6):
        zz = z0 + 0.08 + k * (L - 0.16) / 5
        cyl(en, (mx + 0.01, my + 0.01, zz), (-0.145, 0.49, zz), 0.019, 7, 'cast', caps=(False, False))
    _box(en, (mx - 0.01, my + 0.062, zc + 0.01), (0.12, 0.006, L - 0.10), 'steel')     # heat shield
    # the front of the engine: pulleys on the nose, the alternator low on the left
    pz = z0 - 0.015
    crank = ((0.0, 0.365), 0.070)
    alt = ((-0.20, 0.335), 0.040)
    pump = ((0.0, 0.535), 0.050)
    for (cx, cy), r in (crank, alt, pump):
        _pulley(en, (cx, cy, pz), r, 0.022, 10, 'steel')
    cyl(en, (-0.20, 0.335, pz + 0.02), (-0.20, 0.335, pz + 0.13), 0.055, 8, 'cast')     # the alternator body
    cyl(en, (-0.16, 0.46, zc + 0.05), (-0.18, 0.60, zc + 0.08), 0.004, 5, 'chrome')     # dipstick

    # ---- the belt on the pulleys (declared touching the engine)
    be = part('bay_belt', bevel=0)
    _belt(be, [crank, alt, pump], pz, 0.018, 'rubber')

    # ---- radiator: core, tanks, cap; the shroud with one big fan behind it
    ra = part('bay_radiator', bevel=0)
    rz = z_rad
    rw = 0.33
    r_top = min(hood(x, rz) for x in np.linspace(-rw - 0.02, rw + 0.02, 9)) - HOOD_CLEAR - 0.006   # the nose roof is low and curved
    r_bot = 0.275
    core_y0, core_y1 = r_bot + 0.035, r_top - 0.035
    _box(ra, (0.0, (core_y0 + core_y1) / 2, rz), (2 * rw, core_y1 - core_y0, 0.034), 'cast')             # the core, dark fins
    _box(ra, (0.0, (core_y1 + r_top) / 2, rz), (2 * rw + 0.03, r_top - core_y1, 0.050), 'plastic')       # top tank
    _box(ra, (0.0, (r_bot + core_y0) / 2, rz), (2 * rw + 0.03, core_y0 - r_bot, 0.050), 'plastic')       # bottom tank
    cyl(ra, (-0.22, r_top, rz), (-0.22, r_top + 0.012, rz), 0.024, 8, 'chrome')                          # the pressure cap
    sh = part('bay_shroud', bevel=0)
    sz = rz + 0.05
    sy = (core_y0 + core_y1) / 2
    _box(sh, (0.0, sy, sz + 0.002), (2 * rw, core_y1 - core_y0, 0.004), 'plastic')  # the shroud plate behind the core
    _ring(sh, (0.0, sy, sz + 0.004), 1, 0.130, 0.117, 0.045, 12, 'plastic')
    _fan(sh, (0.0, sy, sz + 0.035), 0.110, 7, 0.034, 'plastic', 'cast')

    # ---- hoses: top hose radiator to the thermostat, bottom hose to the pump
    ho = part('bay_hoses', bevel=0)
    _seg(ho, [(0.22, r_top - 0.02, rz + 0.03), (0.20, r_top, rz + 0.16), (0.08, 0.60, z0 - 0.10), (0.0, 0.57, z0 - 0.06)], 0.020, 7, 'rubber')
    _seg(ho, [(-0.24, r_bot + 0.02, rz + 0.03), (-0.26, r_bot + 0.02, rz + 0.20), (-0.12, 0.33, z0 - 0.09), (-0.06, 0.345, z0 - 0.06)], 0.020, 7, 'rubber')

    # ---- air box front right with a snorkel to the support, and the pipe to the throttle
    ab = part('bay_airbox', bevel=0)
    ax = IN_X - 0.105
    az = rz + 0.26
    _box(ab, (ax, 0.44, az), (0.21, 0.18, 0.22), 'plastic')
    _seg(ab, [(ax, 0.50, az + 0.11), (ax - 0.05, 0.53, z0 - 0.16), (px + 0.02, py, z0 - 0.085)], 0.034, 8, 'rubber')
    _seg(ab, [(ax, 0.40, az - 0.11), (ax, 0.40, rz + 0.16)], 0.030, 8, 'plastic')

    # ---- battery rear right with its cables; fuse box rear left; brake reservoir; washer bottle
    bt = part('bay_battery', bevel=0)
    bx = IN_X - 0.095
    bz = firewall_z - 0.11
    _box(bt, (bx, 0.39, bz), (0.19, 0.17, 0.16), 'plastic')
    _box(bt, (bx, 0.479, bz), (0.19, 0.012, 0.16), 'plastic')
    for sx in (1, -1):
        cyl(bt, (bx + sx * 0.055, 0.485, bz - 0.04), (bx + sx * 0.055, 0.510, bz - 0.04), 0.010, 6, 'chrome')
    _box(bt, (bx, 0.49, bz + 0.07), (0.21, 0.014, 0.012), 'steel')           # the hold-down bar
    cb = part('bay_cables', bevel=0)
    _seg(cb, [(bx + 0.055, 0.51, bz - 0.04), (bx + 0.03, 0.54, bz - 0.09), (0.19, 0.50, z1 - 0.10)], 0.009, 5, 'rubber')
    _seg(cb, [(bx - 0.055, 0.51, bz - 0.04), (bx - 0.08, 0.50, bz + 0.02), (bx - 0.09, 0.36, bz + 0.04)], 0.009, 5, 'rubber')
    fb = part('bay_fusebox', bevel=0)
    fx = -(IN_X - 0.08)
    _box(fb, (fx, 0.57, firewall_z - 0.09), (0.15, 0.05, 0.13), 'plastic')
    _box(fb, (fx, 0.598, firewall_z - 0.09), (0.13, 0.008, 0.11), 'plastic')
    br = part('bay_brake', bevel=0)
    brx, brz = -0.355, firewall_z - 0.065
    _box(br, (brx, 0.63, brz), (0.07, 0.07, 0.05), 'plastic')
    cyl(br, (brx, 0.665, brz), (brx, 0.682, brz), 0.022, 6, 'plastic')
    _box(br, (brx, 0.56, brz), (0.06, 0.07, 0.11), 'cast')     # the master cylinder under it
    wb = part('bay_washer', bevel=0)
    wx = -(IN_X - 0.08)
    _box(wb, (wx, 0.46, rz + 0.26), (0.15, 0.24, 0.16), 'plastic')
    cyl(wb, (wx + 0.03, 0.58, rz + 0.26), (wx + 0.03, 0.605, rz + 0.26), 0.022, 6, 'plastic')

    # ---- strut tops either side: the tower cap with three nuts
    for sx, nm in ((1, 'fr'), (-1, 'fl')):
        st = part('bay_strut_' + nm, bevel=0)
        p = A['strut_top_' + nm]
        top = min(p[1] + 0.020, hood(p[0], p[2]) - HOOD_CLEAR - 0.012)
        cyl(st, (p[0], p[1] - 0.06, p[2]), (p[0], top, p[2]), 0.070, 10, 'under_paint', r_b=0.060)
        cyl(st, (p[0], top, p[2]), (p[0], top + 0.008, p[2]), 0.036, 8, 'cast')
        for k in range(3):
            a = 2 * math.pi * k / 3 + 0.5
            cyl(st, (p[0] + 0.047 * math.cos(a), top, p[2] + 0.047 * math.sin(a)),
                (p[0] + 0.047 * math.cos(a), top + 0.012, p[2] + 0.047 * math.sin(a)), 0.009, 6, 'steel')

    # ---- the wiring loom along the firewall, the prop rod in its clip, the bulb
    lo = part('bay_loom', bevel=0)
    ly = hood(0.0, firewall_z - 0.04) - HOOD_CLEAR - 0.012
    _seg(lo, [(-(TUB_X - 0.05), ly, firewall_z - 0.03), (TUB_X - 0.05, ly, firewall_z - 0.03)], 0.012, 6, 'rubber')
    pr = part('bay_prop_rod', bevel=0)
    rod_y = rs_mid - 0.012
    rod_z = rs_z + 0.040
    _seg(pr, [(-0.46, rod_y, rod_z), (0.46, rod_y, rod_z)], 0.006, 6, 'steel')    # across the support, in its clip
    _box(pr, (-0.30, rod_y, rod_z + 0.004), (0.03, 0.016, 0.018), 'plastic')       # the clip
    _box(pr, (0.44, rod_y, rod_z + 0.004), (0.02, 0.016, 0.018), 'plastic')        # the hinge end's bracket
    bu = part('bay_bulb', bevel=0)
    by = hood(0.38, firewall_z - 0.05) - HOOD_CLEAR - 0.04
    _box(bu, (0.38, by, firewall_z - 0.025), (0.09, 0.03, 0.03), 'plastic')
    _box(bu, (0.38, by, firewall_z - 0.045), (0.07, 0.022, 0.012), 'glow_lens')


BAYS = {'p1_coupe': coupe_bay}
