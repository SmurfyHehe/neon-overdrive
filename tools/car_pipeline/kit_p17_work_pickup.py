"""P17, the work pickup (Camel): what it adds to the common parts recipe.

A late-1990s mid-size four-door double cab on a 3.18 m wheelbase with a short
open bed (sheet: notes/car-sheets/p17_work_pickup-2026-10-10; Roy 439-449,
1219, 1475). Visual rebuild only: the loft, the dimensions and everything the
car drives on stay as tools/fleet_design/cars.py P17 has them.

What it has that the common recipe does not:
  - four doors: the front pair is the common one, the rear pair (`door_rr`,
    `door_rl`) is cut here from the B-pillar back to the C-pillar, each on its
    own hinge with its glass, seal and handle
  - the bed as a bolted-on box of its own (`bed`): a shut line round the cab's
    back wall, the black liner (the loft's `bed` floor and walls), black rail
    caps, and the tailgate (`tailgate`) cut out of the tail between the lamps,
    hinged at its bottom edge so it folds down level with the bed floor
  - a chrome-framed three-bar grille between wide head lamps with an amber
    block on the outer third, a chrome front bumper the plate lies on
  - stacked three-segment tail lamps at the bed corners (sheet section 6):
    red top (running lamp with the brake core), a clear middle (reversing lamp
    inboard, the blinker's amber bulb outboard; both dark until lit, so at
    100 m each lamp is two red dots with a dark gap), red bottom
  - a high brake lamp at the top of the rear glass, a sliding centre pane
  - the sodium side stripe and its dark pinline as paint regions, so each door
    carries its own piece of it and nothing is laid over the shut lines
  - 300 mm discs in front, 260 mm drums at the rear (sheet, CarFittings),
    a chrome hub cap on each steel wheel
  - ladder frame, leaf-sprung live axle, pumpkin diff, driveshaft, tank on the
    left, one exhaust down the right to the rear corner (Roy 444)

Kept in its own file so car rebuilds can run side by side; kits.KITS imports
KIT from here. The helpers are kits.py's; the mirrors, the slider and the
bay boxes follow the street truck's (kit_p10_truck.py).
"""
import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl

# ---- panels (s along the length from the nose, metres; front/rear view x, y)
REAR_DOOR = (2.60, 3.18)             # rear door: B-pillar trailing edge to the C-pillar (side glass ends at 3.18)
BED_S = 3.37                         # the bed box starts here: the shut line behind the cab's back wall
TAILGATE_HW, TAILGATE_Y0 = 0.74, 0.80   # between the lamp columns, down to the bed floor (0.84)
TAILGATE_S = 4.755                   # its inner skin (the bed's end wall) starts at 4.758

# ---- lamps
HEAD = (0.54, 0.74, 0.72, 0.88)      # head lamp, right side (front view): the warm white part
TURN_F = (0.73, 0.75, 0.82, 0.87)    # the amber block on its outer third
GRILLE = (0.50, 0.70, 0.90)          # half width, bottom, top: chrome frame, three chrome bars, black behind
LAMP_X = (0.76, 0.87)                # tail lamp column, right side (rear view)
LAMP_TOP = (0.95, 1.06)              # red: running lamp, the brake lamp as its core
LAMP_MID = (0.84, 0.945)             # clear: reversing lamp inboard, blinker outboard
LAMP_MID_SPLIT = 0.815
LAMP_LOW = (0.72, 0.835)             # red: running lamp
BRAKE_C = (-0.15, 1.655, 0.15, 1.695)   # the high brake lamp at the top of the rear glass
SLIDER = (-0.26, 1.30, 0.26, 1.58)   # the sliding centre pane of the rear window
BUMPER_F = (0.46, 0.58)              # chrome front bumper, bottom and top
BUMPER_IN = 0.30                     # flat under the plate inboard of this, 30 mm proud outboard of it

# ---- the stripe (cars.py P17 decals: sodium band, dark pinline under it), as paint regions
STRIPE = (0.40, 4.60, 0.74, 0.82)
PINLINE = (0.40, 4.60, 0.715, 0.735)

# ---- running gear and small parts
DISC_F, DRUM_R = 0.15, 0.13          # 300 mm discs in front, 260 mm drums at the rear
FLAP = (3.62, 0.98)                  # fuel flap on the left bed side, behind the cab: s, y
ANTENNA = (0.78, 1.05)               # the mast on the right front fender: x, s
PLATES = {'plate_f': ('front', 0.52, 0.26, 0.055), 'plate_r': ('rear', 0.70, 0.26, 0.055)}


def _decal(ctx, d):
    """Every sheet decal of this car is a part of its own (fittings) or a paint region (the stripe)."""
    return True


def _sheet_part(ctx, p):
    """The door mirrors swing with the front doors."""
    if p['type'] != 'mirrors':
        return False
    pm = fcar.CarModel(ctx.D)
    fcar.add_part(pm, p)
    for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
        tri = np.array(tri)
        nm = 'l' if tri[:, 0].mean() < 0 else 'r'
        ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
    return True


def _cuts(D, R, z, cut):
    """The rear doors out of the side, the tailgate out of the tail, then the
    bed box off the cab (fixed both sides: a shut line with its floor)."""
    s0, s1 = REAR_DOOR
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 3) & (ps.col(0) <= 7))(sx)
        cut('door_r' + nm, [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((0, 1, 0), R['door_y0'])], side, True)
    gate = lambda ps: ~ps.mat_is('glass')
    planes = [((0, 0, 1), z(TAILGATE_S)), ((1, 0, 0), -TAILGATE_HW), ((-1, 0, 0), -TAILGATE_HW), ((0, 1, 0), TAILGATE_Y0)]
    cut('tailgate', planes, gate, True)
    # the bed is cut from what the tailgate left, so it carries the tailgate's shut line: a floor under
    # the bottom and inner edges; along the sides an edge return instead, as the tailgate's own, so the
    # tailgate (3 cm thick at its bed wall) folds down past it without sweeping through a floor
    side = lambda n: abs(n[0]) > 0.5
    round_gate = [(-np.asarray(n, float), -(d - P.GAP / 2), side(n), not side(n)) for n, d in planes]
    cut('bed', [((0, 0, 1), z(BED_S))], gate, False, [True], edges=round_gate)
    return ['door_rr', 'door_rl', 'tailgate', 'bed']


def _blade(ctx, name, y0, y1, proud):
    """The chrome front bumper: flat under the plate, standing proud outboard
    of it, with a short return round each corner (the muscle's recipe)."""
    D, z = ctx.D, ctx.z
    hw = pl(D['hw'], 0.0)
    blade = ctx.part(name, bevel=0)
    K.lay(ctx, blade, 'front', K.rect2(-BUMPER_IN - 0.01, y0, BUMPER_IN + 0.01, y1), 'chrome', 0.012)
    yc, h = (y0 + y1) / 2, y1 - y0
    for sx in (1, -1):
        xa, xb = sx * BUMPER_IN, sx * (hw + 0.012)
        P.obox(blade, ((xa + xb) / 2, yc, z(0.0) - proud / 2), (abs(xb - xa), h, proud), np.eye(3), 'chrome')
        run = (0.0, 0.08, 0.24)
        pts = [np.array([sx * (pl(D['hw'], s_) + 0.006), yc, z(s_)]) for s_ in run]
        for a, b in zip(pts, pts[1:]):
            P.obox(blade, (a + b) / 2, (np.linalg.norm(b - a) + 0.012, h * 0.8, 0.014), P.frame_basis(b - a, (0, 1, 0)), 'chrome')
    # the black valance under it
    K.lay(ctx, blade, 'front', K.rect2(-hw + 0.04, y0 - 0.06, hw - 0.04, y0 - 0.002), 'plastic', 0.004)
    return blade


def _frame(ctx, part, view, x0, y0, x1, y1, w, off, mat='chrome'):
    """A rectangular frame of four strips, `w` wide, laid `off` proud."""
    K.lay(ctx, part, view, K.rect2(x0, y1 - w, x1, y1), mat, off)
    K.lay(ctx, part, view, K.rect2(x0, y0, x1, y0 + w), mat, off)
    K.lay(ctx, part, view, K.rect2(x0, y0 + w, x0 + w, y1 - w), mat, off)
    K.lay(ctx, part, view, K.rect2(x1 - w, y0 + w, x1, y1 - w), mat, off)


def _fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R

    # ---- the nose: chrome-framed three-bar grille, wide lamps with amber outer blocks, chrome bumper
    ghw, gy0, gy1 = GRILLE
    gr = part('grille', bevel=0)
    K.lay(ctx, gr, 'front', K.rect2(-ghw, gy0, ghw, gy1), 'rubber', 0.003)
    _frame(ctx, gr, 'front', -ghw, gy0, ghw, gy1, 0.022, 0.012)
    for k in range(3):
        yc = gy0 + (gy1 - gy0) * (k + 1) / 4
        K.lay(ctx, gr, 'front', K.rect2(-ghw + 0.02, yc - 0.011, ghw - 0.02, yc + 0.011), 'chrome', 0.010)
    hx0, hy0, hx1, hy1 = HEAD
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        xa, xb = sorted((sx * hx0, sx * TURN_F[2]))
        K.lay(ctx, head, 'front', K.rect2(xa - 0.008, hy0 - 0.008, xb + 0.008, hy1 + 0.008), 'plastic', 0.004)   # the housing
        xa, xb = sorted((sx * hx0, sx * hx1))
        K.lay(ctx, head, 'front', K.rect2(xa, hy0, xb, hy1), 'glow_lens', 0.007)
        q = K.lay(ctx, head, 'front', K.ellipse(0.5 * (xa + xb), 0.5 * (hy0 + hy1), 0.050, 0.042, 8), 'glow_head', 0.009)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = K.lamp_centre(q)
        xa, xb = sorted((sx * TURN_F[0], sx * TURN_F[2]))
        K.lay(ctx, part('turn_f' + nm, bevel=0), 'front', K.rect2(xa, TURN_F[1], xb, TURN_F[3]), 'glow_turn', 0.007)
    _blade(ctx, 'bumper_blade_f', BUMPER_F[0], BUMPER_F[1], 0.03)

    # ---- the tail: a stacked three-segment lamp at each bed corner in a black housing
    lx0, lx1 = LAMP_X
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * lx0, sx * lx1))
        col = part('lamp_block_' + nm, bevel=0)
        K.lay(ctx, col, 'rear', K.rect2(xa - 0.008, LAMP_LOW[0] - 0.008, xb + 0.008, LAMP_TOP[1] + 0.008), 'plastic', 0.003)
        q = K.lay(ctx, part('tail_' + nm, bevel=0), 'rear', K.rect2(xa, LAMP_TOP[0], xb, LAMP_TOP[1]), 'glow_tail', 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = K.lamp_centre(q)
        K.lay(ctx, part('brake_' + nm, bevel=0), 'rear', K.rect2(xa + 0.015, LAMP_TOP[0] + 0.015, xb - 0.015, LAMP_TOP[1] - 0.015),
              'glow_brake', 0.009)
        ia, ib = sorted((sx * lx0, sx * LAMP_MID_SPLIT))
        K.lay(ctx, part('reverse_' + nm, bevel=0), 'rear', K.rect2(ia, LAMP_MID[0], ib, LAMP_MID[1]), 'glow_reverse', 0.006)
        oa, ob = sorted((sx * (LAMP_MID_SPLIT + 0.005), sx * lx1))
        K.lay(ctx, part('turn_r' + nm, bevel=0), 'rear', K.rect2(oa, LAMP_MID[0], ob, LAMP_MID[1]), 'glow_turn', 0.006)
        K.lay(ctx, part('tail_low_' + nm, bevel=0), 'rear', K.rect2(xa, LAMP_LOW[0], xb, LAMP_LOW[1]), 'glow_tail', 0.006)
    # the high brake lamp at the top of the rear glass
    cx0, cy0, cx1, cy1 = BRAKE_C
    hb = part('brake_c', bevel=0)
    K.lay(ctx, hb, 'rear', K.rect2(cx0 - 0.01, cy0 - 0.01, cx1 + 0.01, cy1 + 0.01), 'plastic', 0.004)
    K.lay(ctx, hb, 'rear', K.rect2(cx0, cy0, cx1, cy1), 'glow_brake', 0.006)
    # the rear window's sliding centre pane: a rubber frame with its own glass
    sl = part('glass_slider', bevel=0)
    sx0, sy0, sx1, sy1 = SLIDER
    K.lay(ctx, sl, 'rear', K.rect2(sx0 - 0.02, sy0 - 0.02, sx1 + 0.02, sy1 + 0.02), 'rubber', 0.003)
    K.lay(ctx, sl, 'rear', K.rect2(sx0, sy0, sx1, sy1), 'glass', 0.005)
    K.lay(ctx, sl, 'rear', K.rect2(-0.006, sy0, 0.006, sy1), 'rubber', 0.006)
    # the lamp over the rear plate
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, pl_y + 0.024)], 0.026)
    if c is not None:
        P.obox(part('plate_lamp', bevel=0), c[0], (0.12, 0.018, 0.024), np.eye(3), 'plastic', {'-y': 'glow_lens'})

    # ---- the tailgate: hinged at its bottom edge, folds down level with the bed floor; a pull at the top
    th = part('handle_tailgate', parent='hinge_tailgate', bevel=0)
    K.lay(ctx, th, 'rear', K.rect2(-0.10, 1.045, 0.10, 1.085), 'rubber', 0.002)
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, 1.065)], 0.009)
    if c is not None:
        P.obox(th, c[0], (0.16, 0.014, 0.014), np.eye(3), 'chrome')
    hinges = ctx.info.setdefault('hinges', {})
    hinges['hinge_tailgate'] = {'pos': [0.0, TAILGATE_Y0, round(float(z(L)), 4)], 'axis': [1, 0, 0], 'open_sign': 1,
                                'open_deg': 90, 'panel': 'tailgate'}

    # ---- the doors swing on the outer skin at their front shut line, as real hinges do: the
    # common hinge 2 cm inboard swings the front edge forward into the fender (part_fit, #674)
    s0, s1 = REAR_DOOR
    for door, s_h in (('door_', R['door_s0']), ('door_r', s0)):
        belt = pl(D['belt'], s_h)
        for sx, nm in ((1, 'r'), (-1, 'l')):
            hinges['hinge_' + door + nm] = {
                'pos': [round(float(sx * pl(D['hw'], s_h)), 4), round(float(0.5 * (R['door_y0'] + belt)), 4), round(float(z(s_h)), 4)],
                'axis': [0, 1, 0], 'open_sign': sx, 'open_deg': 60, 'panel': door + nm}
    # the hood on gooseneck hinges: the pivot a little above and behind its rear edge, so every
    # point of the hood rises and moves forward as it opens, instead of its rear corners dipping
    # into the fenders or its rear edge swinging back into the wipers and the screen (part_fit, #675)
    hinges['hinge_hood'] = {'pos': [0.0, round(float(pl(D['top'], cab['A']) + 0.01), 4), round(float(z(cab['A'] + 0.01)), 4)],
                            'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': 45, 'panel': 'hood'}
    # the wipers' pivots stand on the cowl behind the hood's rear edge, not on the hood: the common
    # pivot 12 mm ahead of the screen is under the hood and the hood opens through it (part_fit)
    sA = cab['A']
    s_w = sA + 0.075
    g0, g1 = ctx.on_top(0.3, sA + 0.05), ctx.on_top(0.3, sA + 0.30)
    up_glass = (g1 - g0) / np.linalg.norm(g1 - g0)
    n_glass = np.cross(np.array([1.0, 0, 0]), up_glass)
    if n_glass[1] < 0:
        n_glass = -n_glass
    for nm, x0, x1 in (('r', 0.06, 0.52), ('l', -0.50, -0.04)):
        wp = part('wiper_' + nm, bevel=0)
        wp.polys, wp.mats, wp.kind, wp.shut = [], [], [], []
        a_, b_ = ctx.on_top(x0, s_w) + n_glass * 0.012, ctx.on_top(x1, s_w) + n_glass * 0.012
        P.obox(wp, (a_ + b_) / 2, (np.linalg.norm(b_ - a_), 0.012, 0.016), P.frame_basis(b_ - a_, n_glass), 'rubber')
        pivot = ctx.on_top(x0 + 0.02, sA + 0.018) + n_glass * 0.010
        mid = (a_ + b_) / 2 + n_glass * 0.010
        P.obox(wp, (pivot + mid) / 2, (np.linalg.norm(mid - pivot), 0.008, 0.012), P.frame_basis(mid - pivot, n_glass), 'plastic')

    # the door glass seal does not run on under the A-pillar strip (which lies over the glass edge)
    for nm in ('r', 'l'):
        seal = ctx.parts.get('seal_door_' + nm)
        if seal is None:
            continue
        keep = [i for i, q in enumerate(seal.polys)
                if not (q.mean(axis=0)[2] < z(cab['W']) and q.mean(axis=0)[1] > pl(D['belt'], R['door_s0']) + 0.02)]
        for attr in ('polys', 'mats', 'kind', 'shut'):
            setattr(seal, attr, [getattr(seal, attr)[i] for i in keep])
    hs = s1 - 0.16
    hy = pl(D['belt'], hs) - 0.075
    for sx, nm in ((1, 'r'), (-1, 'l')):
        view = 'right' if sx > 0 else 'left'
        hp = part('handle_r' + nm, parent='hinge_door_r' + nm, bevel=0)
        K.lay(ctx, hp, view, K.rect2(z(hs - 0.065), hy - 0.022, z(hs + 0.065), hy + 0.022), 'rubber', 0.002)
        c = P.laid_on(ctx.body_tris, view, [(z(hs), hy)], 0.009)
        if c is not None:
            P.obox(hp, c[0], (0.014, 0.016, 0.105), np.eye(3), 'chrome')

    # ---- the bed: black plastic caps along both rails, a tie-down at each corner of the floor
    cap = part('bed_rails', bevel=0)
    s_a, s_b = BED_S + 0.05, TAILGATE_S - 0.02
    for s_ in np.linspace(s_a, s_b, 4)[:-1]:
        t_ = s_ + (s_b - s_a) / 3
        xo0, xo1 = pl(D['hw'], s_) - 0.075, pl(D['hw'], t_) - 0.075
        xi0, xi1 = xo0 - 0.07, xo1 - 0.07
        y = 1.13 + 0.006
        q = [np.array([xi0, y, z(s_)]), np.array([xo0, y, z(s_)]), np.array([xo1, y, z(t_)]), np.array([xi1, y, z(t_)])]
        cap.add(P.facing([q], (0, 1, 0))[0], 'plastic')
    for s_ in (BED_S + 0.12, TAILGATE_S - 0.10):
        P.obox(part('bed_hooks', bevel=0), (0.70, 0.86, z(s_)), (0.04, 0.03, 0.05), np.eye(3), 'steel')

    # ---- brakes: the front caliper stays on the upright (the disc is in the wheel's mesh)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        cal = part('caliper_f' + nm, bevel=0)
        hub_x = sx * (wh['track'] / 2 - wh['w'] / 2 - 0.018)
        P.obox(cal, (hub_x, r_w + DISC_F - 0.035, z(axles[0])), (0.04, 0.07, 0.12), np.eye(3), 'steel')

    # ---- fuel flap on the left bed side, behind the cab (the tank hangs ahead of the rear axle, left)
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])

    # ---- antenna: one mast on the right front fender
    base = ctx.on_top(ANTENNA[0], ANTENNA[1])
    if base is not None:
        an = part('antenna', bevel=0)
        K.cyl(an, base, base + np.array([0.0, 0.70, 0.10]), 0.004, 3, 'rubber', caps=(False, False), r_b=0.002)
        P.obox(an, base + np.array([0, 0.006, 0]), (0.034, 0.014, 0.034), np.eye(3), 'plastic')

    # ---- under the hood: a dark bay floor and the radiator. No engine model yet (engine bays B).
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    P.obox(part('bay_floor', bevel=0), (0.0, 0.52, z(hood_mid)), (1.10, 0.02, cab['A'] - R['nose_s'] - 0.12), np.eye(3), 'rubber')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.715, z(R['nose_s'] + 0.10)), (0.86, 0.37, 0.05), np.eye(3), 'rubber')

    # ---- the underside: ladder frame rails under the 0.28 belly, crossmembers,
    # the front arms in the wells, a live axle on leaf springs with a pumpkin
    # diff, the driveshaft, the tank on the left, the exhaust down the right.
    fr = part('frame', bevel=0)
    for sx in (1, -1):
        P.obox(fr, (sx * 0.46, 0.255, z(2.40)), (0.08, 0.05, 4.10), np.eye(3), 'steel')
    for s_ in (0.55, 1.40, 3.40, 4.45):
        P.obox(fr, (0.0, 0.255, z(s_)), (0.84, 0.045, 0.06), np.eye(3), 'steel')
    for sx, nm in ((1, 'r'), (-1, 'l')):
        arm = part('susp_f' + nm, bevel=0)
        K.cyl(arm, (sx * 0.42, 0.29, z(axles[0] - 0.12)), (sx * 0.70, r_w - 0.06, z(axles[0])), 0.018, 4, 'steel', caps=(False, True))
        K.cyl(arm, (sx * 0.42, 0.29, z(axles[0] + 0.16)), (sx * 0.70, r_w - 0.06, z(axles[0])), 0.018, 4, 'steel', caps=(False, False))
        K.cyl(arm, (sx * 0.66, r_w - 0.02, z(axles[0])), (sx * 0.60, r_w + 0.30, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        # the cab's rocker pinch flange: a black lip hanging under the floor
        # pan between the arches, below the running board (the cab floor sits
        # on the belly, so without it the cabin's floor edge shows from the side)
        P.obox(part('rocker_' + nm, bevel=0), (sx * 0.86, 0.235, z(2.36)), (0.02, 0.11, 1.92), np.eye(3), 'plastic')
        leaf = part('leaf_' + nm, bevel=0)
        P.obox(leaf, (sx * 0.62, 0.30, z(axles[1])), (0.07, 0.025, 1.15), np.eye(3), 'steel')
        P.obox(leaf, (sx * 0.62, 0.335, z(axles[1])), (0.09, 0.05, 0.14), np.eye(3), 'steel')   # the U-bolt plate
    ax = part('axle_r', bevel=0)
    K.cyl(ax, (-0.70, r_w, z(axles[1])), (0.70, r_w, z(axles[1])), 0.040, 6, 'steel', caps=(False, False))
    dc = part('diff_cover', bevel=0)
    c0 = np.array([0.0, 0.31, z(axles[1])])
    K.cyl(dc, c0 - np.array([0, 0, 0.06]), c0 + np.array([0, 0, 0.12]), 0.09, 8, 'steel', caps=(True, True))
    ds = part('driveshaft', bevel=0)
    K.cyl(ds, (0.0, 0.25, z(1.70)), (0.0, 0.29, z(axles[1] - 0.06)), 0.035, 6, 'steel', caps=(True, False))
    P.obox(part('fuel_tank', bevel=0), (-0.30, 0.225, z(axles[1] - 0.70)), (0.42, 0.10, 0.70), np.eye(3), 'plastic')
    tip = D['exhaust'][0]
    pipe = part('exhaust_pipe', bevel=0)
    pts = [(0.30, 0.25, 1.20), (0.32, 0.22, 1.60), (0.32, 0.22, 3.30), (0.56, 0.24, 3.55), (0.60, 0.26, 4.40),
           (tip['x'], tip['y'], L - 0.02)]
    for (xa, ya, sa), (xb, yb, sb) in zip(pts, pts[1:]):
        K.cyl(pipe, (xa, ya, z(sa)), (xb, yb, z(sb)), 0.028, 5, 'steel', caps=(False, False))
    P.obox(part('muffler', bevel=0), (0.32, 0.215, z(2.80)), (0.20, 0.11, 0.60), np.eye(3), 'steel')


def _wheel(D, tag, sx, axle, part):
    tw = D['wheel']['w']
    if axle == 0:
        K.disc_brake(part, sx, tw, r=DISC_F)
    else:
        K.drum(part, sx, tw, r=DRUM_R)
    K.hubcap(part, sx, tw, r=0.07, h=0.025)


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    cab = D['cabin']
    axles = fcar._axles(D)
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['bay_engine'] = {'pos': [0, 0.70, z(hood_mid + 0.10)]}       # where the V6 goes
    A['bay_radiator'] = {'pos': [0.0, 0.715, z(R['nose_s'] + 0.10)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A['diff'] = {'pos': [0, 0.31, z(axles[1])]}
    A['tank'] = {'pos': [-0.30, 0.225, z(axles[1] - 0.70)]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'regions': {
        'nose_s': 0.22,                    # the front fascia under the grille and lamps
        'door_s0': 1.34, 'door_s1': 2.52,  # the front door; the rear one is cut in _cuts
        'tail_s': 4.55, 'tail_y': 0.46,    # the lower rear apron the step bumper bolts to
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is the tailgate (cuts), the deck the open bed
    'no_antenna': True,                    # the kit stands its own, on the right front fender
    'hinge_of': {'tailgate': 'hinge_tailgate',
                 'door_rr': 'hinge_door_rr', 'door_rl': 'hinge_door_rl',
                 'glass_door_rr': 'hinge_door_rr', 'glass_door_rl': 'hinge_door_rl'},
    # the side stripe runs nose to tailgate across every panel it meets
    'paint_regions': [STRIPE + ('paint_primer',), PINLINE + ('plastic',)],
    'plates': PLATES,
    'asymmetric': {
        'fuel_recess': 'one filler, on the left bed side behind the cab',
        'fuel_flap': 'one filler, on the left bed side behind the cab',
        'antenna': 'one mast, on the right front fender',
        'fuel_tank': 'the tank hangs ahead of the rear axle on the left',
        'exhaust': 'one oval tip, out the right rear corner (Roy 444)',
        'exhaust_pipe': 'one pipe, down the right side to the rear corner',
        'muffler': 'one muffler, on the right under the cab',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'disc 300 mm, single-pot caliper', 'rear': 'drum 260 mm'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 2, 'blinkers_front': 2, 'blinkers_rear': 2,
              'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1, 'wipers': 2, 'fuel_flap': 1,
              'condition': 0.5},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
