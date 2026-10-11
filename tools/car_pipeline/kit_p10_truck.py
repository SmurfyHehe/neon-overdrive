"""P10, the street truck (Harlan Drover): what it adds to the common parts recipe.

A lowered 1993-99 style regular-cab short-bed sport truck with a pushrod V8:
one level line from the cab back to the tailgate top (a hard bed cover flush
with the rails, cut as its own fixed panel), a single upright cab, a real
60 mm cab-to-bed gap in the loft, a roll-pan tail with tall lamp blocks at
the extreme corners and a high brake lamp at the top of the rear glass, no
rear bumper. Black trim era: satin-black nose cap and roll pan, black plastic
grille, no chrome. Bone over Black: the paint above the 0.82 m shoulder
crease, satin black below it (`paint_regions`). Vented discs on all four
wheels, five real spokes. Front engine, rear drive, a live axle on leaf
springs under the bed. MC2 brief, 2026-10-11.

Kept in its own file so car rebuilds can run side by side; kits.KITS imports
KIT from here. The helpers are kits.py's; the spoked wheel face is the hot
hatch's.
"""
import math

import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl
from kit_p2_hothatch import alloy_face

HEAD = (0.33, 0.74, 0.75, 0.88)     # head lamp rect, right side (front view): twin wide rectangles 0.42 x 0.14
TURN_F = (0.33, 0.705, 0.75, 0.725)  # the amber marker line under each
GRILLE = (-0.78, 0.70, 0.78, 0.92)   # the full-width black mesh grille the lamps sit flush in
BLOCK = (0.79, 0.58, 0.91, 1.04)     # tail lamp block, right side (rear view): 0.12 x 0.46 at the roll-pan corner
BLOCK_REV = (0.58, 0.64)             # the white reversing strip at its lower end
BLOCK_TURN = (0.945, 1.04)           # the red blinker at its top (era: red)
BLOCK_BRAKE = (0.70, 0.88)           # the brake core inside the running lamp
BRAKE_C = (-0.15, 1.52, 0.15, 1.58)  # the high brake lamp at the top of the rear glass, 0.30 x 0.06
SLIDER = (-0.24, 1.20, 0.24, 1.48)   # the sliding centre pane of the rear window
TAILGATE_HW, TAILGATE_Y0 = 0.76, 0.56   # the tailgate: between the lamp blocks, down to the roll pan
COVER = (2.86, 4.96, 0.78)           # the hard bed cover: s0, s1, half width (cut flush with the rails)
DISC_F, DISC_R = 0.165, 0.15         # 330 / 300 mm vented discs
FLAP = (2.95, 0.92)                  # the fuel flap on the left bed side, just behind the cab: s, y
ANTENNA = (0.76, 1.00)               # the mast on the right front fender: x, s
DOME = ((0.0, 0.30, 0.45), (0.40, 0.60, 0.95, 1.18), (0.0, 0.025, 0.025, 0.010))   # one wide low power dome
PLATES = {'plate_f': ('front', 0.42, 0.26, 0.055), 'plate_r': ('rear', 0.44, 0.26, 0.055)}


def _decal(ctx, d):
    """Every sheet decal of this car is a part of its own in the fittings."""
    return True


def _sheet_part(ctx, p):
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
    """The tailgate out of the tail face (hinged at its bottom edge) and the
    hard bed cover out of the deck (fixed, flush, a shut line all round)."""
    tail = lambda ps: ps.col(0) == -2
    cut('tailgate', [((1, 0, 0), -TAILGATE_HW), ((-1, 0, 0), -TAILGATE_HW), ((0, 1, 0), TAILGATE_Y0)], tail, True)
    top = lambda ps: (ps.col(0) >= 8) & ~ps.mat_is('glass')
    s0, s1, hw = COVER
    cut('bed_cover', [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((1, 0, 0), -hw), ((-1, 0, 0), -hw)], top, False, [True] * 4)
    return ['tailgate', 'bed_cover']


def _poly(part, pts, out, mat='paint', kind=P.SKIN):
    q = []
    for p in pts:
        p = np.asarray(p, float)
        if not any(np.linalg.norm(p - o) < 1e-5 for o in q):
            q.append(p)
    if len(q) < 3:
        return
    if len(q) == 4:
        for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
            if np.linalg.norm(P.poly_normal(np.array(tri))) > 1e-8:
                part.add(P.facing([tri], out)[0], mat, kind)
        return
    if np.linalg.norm(P.poly_normal(np.array(q))) > 1e-8:
        part.add(P.facing([q], out)[0], mat, kind)


def _fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R

    # ---- the nose: a full-width black mesh grille, the two wide lamps flush in it
    gx0, gy0, gx1, gy1 = GRILLE
    gr = part('grille', bevel=0)
    K.lay(ctx, gr, 'front', K.rect2(gx0, gy0, gx1, gy1), 'rubber', 0.003)
    hx0, hy0, hx1, hy1 = HEAD
    for k in range(4):                                   # the mesh bars, between the lamps
        yc = gy0 + (gy1 - gy0) * (k + 1) / 5
        K.lay(ctx, gr, 'front', K.rect2(-(hx0 - 0.02), yc - 0.005, hx0 - 0.02, yc + 0.005), 'plastic', 0.007)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        xa, xb = sorted((sx * hx0, sx * hx1))
        K.lay(ctx, head, 'front', K.rect2(xa, hy0, xb, hy1), 'plastic', 0.005)             # the black bezel
        K.lay(ctx, head, 'front', K.rect2(xa + 0.010, hy0 + 0.010, xb - 0.010, hy1 - 0.010), 'glow_lens', 0.007)
        q = K.lay(ctx, head, 'front', K.ellipse(0.5 * (xa + xb), 0.5 * (hy0 + hy1), 0.055, 0.040, 8), 'glow_head', 0.009)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = K.lamp_centre(q)
        xa, xb = sorted((sx * TURN_F[0], sx * TURN_F[2]))
        K.lay(ctx, part('turn_f' + nm, bevel=0), 'front', K.rect2(xa, TURN_F[1], xb, TURN_F[3]), 'glow_turn', 0.007)

    # ---- the tail: a tall block at each roll-pan corner. Reversing lamp at
    # the bottom, the running lamp with the brake core in it, the red blinker
    # at the top (era). From the driver's mirror the block is dark, not lit.
    bx0, by0, bx1, by1 = BLOCK
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * bx0, sx * bx1))
        col = part('lamp_block_' + nm, bevel=0)
        K.lay(ctx, col, 'rear', K.rect2(xa - 0.008, by0 - 0.008, xb + 0.008, by1 + 0.008), 'plastic', 0.003)
        K.lay(ctx, col, 'rear', K.rect2(xa - 0.008, by0 - 0.008, xb + 0.008, by1 + 0.008), 'plastic', 0.002, back=True)
        K.lay(ctx, part('reverse_' + nm, bevel=0), 'rear', K.rect2(xa, BLOCK_REV[0], xb, BLOCK_REV[1]), 'glow_reverse', 0.006)
        q = K.lay(ctx, part('tail_' + nm, bevel=0), 'rear', K.rect2(xa, BLOCK_REV[1] + 0.005, xb, BLOCK_TURN[0] - 0.005), 'glow_tail', 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = K.lamp_centre(q)
        K.lay(ctx, part('brake_' + nm, bevel=0), 'rear', K.rect2(xa + 0.015, BLOCK_BRAKE[0], xb - 0.015, BLOCK_BRAKE[1]), 'glow_brake', 0.009)
        K.lay(ctx, part('turn_r' + nm, bevel=0), 'rear', K.rect2(xa, BLOCK_TURN[0], xb, BLOCK_TURN[1]), 'glow_tail', 0.006)
    # the high brake lamp at the top of the rear glass, inside the cab
    cx0, cy0, cx1, cy1 = BRAKE_C
    hb = part('brake_c', bevel=0)
    K.lay(ctx, hb, 'rear', K.rect2(cx0 - 0.01, cy0 - 0.01, cx1 + 0.01, cy1 + 0.01), 'plastic', 0.004)
    K.lay(ctx, hb, 'rear', K.rect2(cx0, cy0, cx1, cy1), 'glow_brake', 0.006)
    # the rear window's sliding centre pane: a rubber frame with its own glass
    sl = part('glass_slider', bevel=0)
    sx0, sy0, sx1, sy1 = SLIDER
    K.lay(ctx, sl, 'rear', K.rect2(sx0 - 0.02, sy0 - 0.02, sx1 + 0.02, sy1 + 0.02), 'rubber', 0.003)
    K.lay(ctx, sl, 'rear', K.rect2(sx0, sy0, sx1, sy1), 'glass', 0.005)
    K.lay(ctx, sl, 'rear', K.rect2(-0.006, sy0, 0.006, sy1), 'rubber', 0.006)        # the centre meeting rail
    # the lamp over the rear plate, in the roll pan
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, pl_y + 0.024)], 0.026)
    if c is not None:
        lamp = part('plate_lamp', bevel=0)
        P.obox(lamp, c[0], (0.12, 0.018, 0.024), np.eye(3), 'plastic', {'-y': 'glow_lens'})
    # the tailgate's pull, a recessed black handle at the top centre
    th = part('handle_tailgate', parent='hinge_tailgate', bevel=0)
    K.lay(ctx, th, 'rear', K.rect2(-0.08, 0.985, 0.08, 1.025), 'rubber', 0.002)
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, 1.005)], 0.009)
    if c is not None:
        P.obox(th, c[0], (0.14, 0.014, 0.014), np.eye(3), 'plastic')
    ctx.info.setdefault('hinges', {})['hinge_tailgate'] = {
        'pos': [0.0, TAILGATE_Y0, round(float(z(L)), 4)], 'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': 85, 'panel': 'tailgate'}

    # ---- the hood's one wide low power dome: 0.9 m wide, 25 mm tall, fading in from the nose
    dome = part('hood_dome', parent='hinge_hood', bevel=0)
    xs, ss, lift = DOME
    rows = []
    for s_, h in zip(ss, lift):
        base = [np.asarray(ctx.on_top(x, s_, 0.001), float) for x in xs]
        rows.append([base[0] + np.array([0, h, 0]), base[1] + np.array([0, h, 0]), base[2]])
    up = np.array([0.0, 1.0, 0.0])
    for a, b in zip(rows, rows[1:]):
        _poly(dome, (a[0], a[1], b[1], b[0]), up)
        _poly(dome, (a[1], a[2], b[2], b[1]), (0.6, 1, 0))
    dome.add(P.facing([rows[-1]], (0, 0.3, 1))[0], 'paint', P.SKIN)      # the open end at the cowl

    # ---- brakes: the caliper stays on the upright (the disc is in the wheel's mesh)
    for ai, tagf, dr in ((0, 'f', DISC_F), (1, 'r', DISC_R)):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        track = wh['track'] if ai == 0 else wh.get('track_rear', wh['track'])
        for sx, nm in ((1, 'r'), (-1, 'l')):
            cal = part('caliper_' + tagf + nm, bevel=0)
            hub_x = sx * (track / 2 - tw / 2 - 0.018)
            P.obox(cal, (hub_x, r_w + dr - 0.035, z(axles[ai])), (0.04, 0.07, 0.12), np.eye(3), 'steel')

    # ---- fuel flap on the left bed side, just behind the cab (the tank hangs ahead of the rear axle, left)
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])

    # ---- antenna: one mast on the right front fender
    base = ctx.on_top(ANTENNA[0], ANTENNA[1])
    if base is not None:
        an = part('antenna', bevel=0)
        K.cyl(an, base, base + np.array([0.0, 0.62, 0.10]), 0.004, 3, 'rubber', caps=(False, False), r_b=0.002)
        P.obox(an, base + np.array([0, 0.006, 0]), (0.034, 0.014, 0.034), np.eye(3), 'plastic')

    # ---- under the hood: a dark bay floor and the radiator. No engine model (brief).
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    P.obox(part('bay_floor', bevel=0), (0.0, 0.44, z(hood_mid)), (1.40, 0.02, cab['A'] - R['nose_s'] - 0.10), np.eye(3), 'rubber')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.62, z(R['nose_s'] + 0.10)), (0.86, 0.40, 0.05), np.eye(3), 'rubber')

    # ---- the underside: a ladder frame hanging under the belly (0.14 ground
    # clearance), three crossmembers, the front subframe and its arms in the
    # front wells, a live axle on leaf springs with a finned diff cover, the
    # driveshaft, the tank ahead of the rear axle on the left, the single
    # exhaust down the right to the rear corner.
    fr = part('frame', bevel=0)
    for sx in (1, -1):
        P.obox(fr, (sx * 0.46, 0.17, z(2.60)), (0.08, 0.06, 4.50), np.eye(3), 'steel')
    for s_ in (0.60, 2.20, 4.45):
        P.obox(fr, (0.0, 0.17, z(s_)), (0.84, 0.05, 0.06), np.eye(3), 'steel')
    sub = part('subframe_f', bevel=0)
    P.obox(sub, (0.0, 0.19, z(axles[0] + 0.05)), (1.10, 0.05, 0.30), np.eye(3), 'steel')
    for sx, nm in ((1, 'r'), (-1, 'l')):
        arm = part('susp_f' + nm, bevel=0)
        K.cyl(arm, (sx * 0.40, 0.22, z(axles[0] - 0.10)), (sx * 0.70, r_w - 0.04, z(axles[0])), 0.018, 4, 'steel', caps=(False, True))
        K.cyl(arm, (sx * 0.40, 0.22, z(axles[0] + 0.18)), (sx * 0.70, r_w - 0.04, z(axles[0])), 0.018, 4, 'steel', caps=(False, False))
        K.cyl(arm, (sx * 0.66, r_w - 0.02, z(axles[0])), (sx * 0.60, r_w + 0.30, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        leaf = part('leaf_' + nm, bevel=0)
        P.obox(leaf, (sx * 0.62, 0.30, z(axles[1])), (0.07, 0.02, 1.10), np.eye(3), 'steel')
        P.obox(leaf, (sx * 0.62, 0.34, z(axles[1])), (0.09, 0.06, 0.14), np.eye(3), 'steel')   # the U-bolt plate
    ax = part('axle_r', bevel=0)
    K.cyl(ax, (-0.70, r_w, z(axles[1])), (0.70, r_w, z(axles[1])), 0.040, 6, 'steel', caps=(False, False))
    dc = part('diff_cover', bevel=0)
    c0 = np.array([0.0, r_w, z(axles[1])])
    K.cyl(dc, c0 - np.array([0, 0, 0.04]), c0 + np.array([0, 0, 0.16]), 0.15, 8, 'steel', caps=(True, True))
    for k in range(3):                                   # the fins
        P.obox(dc, c0 + np.array([0, (k - 1) * 0.07, 0.17]), (0.26, 0.012, 0.03), np.eye(3), 'steel')
    ds = part('driveshaft', bevel=0)
    K.cyl(ds, (0.0, 0.30, z(1.95)), (0.0, r_w - 0.02, z(axles[1] - 0.12)), 0.035, 6, 'steel', caps=(True, False))
    tk = part('tank', bevel=0)
    P.obox(tk, (-0.35, 0.215, z(axles[1] - 0.62)), (0.50, 0.15, 0.70), np.eye(3), 'plastic')
    tip = D['exhaust'][0]
    pipe = part('exhaust_pipe', bevel=0)
    pts = [(0.30, 0.26, 1.30), (0.44, 0.17, 1.60), (0.48, 0.17, 3.40), (0.62, 0.20, 3.70), (0.62, 0.20, 4.40), (tip['x'], tip['y'], L + tip.get('out', 0.05) - 0.06)]
    for (xa, ya, sa), (xb, yb, sb) in zip(pts, pts[1:]):
        K.cyl(pipe, (xa, ya, z(sa)), (xb, yb, z(sb)), 0.03, 5, 'steel', caps=(False, False))
    P.obox(part('muffler', bevel=0), (0.55, 0.19, z(4.05)), (0.20, 0.12, 0.60), np.eye(3), 'steel')


def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    dr = DISC_F if axle == 0 else DISC_R
    alloy_face(D, part, sx, tw, dr)           # five real spokes, the disc seen between them
    # vented: a second plate behind the face with the air gap between them, and the hat
    x0 = -sx * tw / 2
    K.cyl(part, (x0 - sx * 0.020, 0, 0), (x0 - sx * 0.028, 0, 0), dr * 0.86, 8, 'plastic', caps=(False, False))
    K.cyl(part, (x0 - sx * 0.028, 0, 0), (x0 - sx * 0.036, 0, 0), dr, 12, 'steel')
    K.cyl(part, (x0, 0, 0), (x0 - sx * 0.036, 0, 0), dr * 0.45, 8, 'steel', caps=(False, False))


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    cab = D['cabin']
    axles = fcar._axles(D)
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['bay_engine'] = {'pos': [0, 0.56, z(hood_mid + 0.10)]}       # where the V8 goes
    A['bay_radiator'] = {'pos': [0.0, 0.62, z(R['nose_s'] + 0.10)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A['diff'] = {'pos': [0, D['wheel']['r'], z(axles[1])]}
    A['tank'] = {'pos': [-0.35, 0.215, z(axles[1] - 0.62)]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'regions': {
        'nose_s': 0.22,                    # the satin-black nose cap under the grille
        'hood_hw': 0.74,
        'door_s0': 1.29, 'door_s1': 2.45,  # one long door a side; the cab's rear quarter is the B-pillar
        'door_y0': 0.36,
        'tail_s': 4.75, 'tail_y': 0.30,    # the roll pan's lower lip, under the plate
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is the tailgate (cuts), the deck the fixed bed cover
    'no_antenna': True,                    # the kit stands its own, on the right front fender
    'hinge_of': {'tailgate': 'hinge_tailgate'},
    # black trim era: the nose cap and the roll pan satin black
    'panel_mats': {'bumper_f': 'plastic', 'bumper_r': 'plastic'},
    # Bone over Black: everything below the 0.82 shoulder crease is satin black trim, nose to tail
    'paint_regions': [(0.0, 5.05, 0.0, 0.82, 'trim')],
    'plates': PLATES,
    'asymmetric': {
        'fuel_recess': 'one filler, on the left bed side behind the cab',
        'fuel_flap': 'one filler, on the left bed side behind the cab',
        'antenna': 'one mast, on the right front fender',
        'tank': 'the tank hangs ahead of the rear axle on the left',
        'exhaust': 'one oval tip, out the right rear corner',
        'exhaust_pipe': 'one pipe, down the right side to the rear corner',
        'muffler': 'one muffler, on the right ahead of the rear axle',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'vented disc 330 mm, single-pot caliper', 'rear': 'vented disc 300 mm, single-pot caliper'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 2, 'blinkers_front': 2, 'blinkers_rear': 2,
              'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1, 'wipers': 2, 'fuel_flap': 1,
              'condition': 0.3},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
