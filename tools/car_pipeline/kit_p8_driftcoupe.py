"""P8, the drift coupe (Ashida Levant, Kasumi Run's car): what it adds to the
common parts recipe.

A 1983-91 style rear-drive box coupe, T2, sheet p8_driftcoupe (MC1,
2026-10-11). Flat slab flanks under a dead-straight belt, thin pillars, a
wedge nose with SLIM pop-up lamps (modelled down, each on its own hinge: the
kei's recipe), four bolt-on riveted overfenders with a polished rolled lip
(the car's one highlight line, with a thin drip rail), three-bar tail
clusters either side of the plate (no high brake lamp: era), one big oval
tip on the right, vented discs on all four wheels behind deep-dish bronze
rims with a polished lip, the fuel flap on the left rear quarter, one primer
front-left fender (a paint-mask panel until the body shop resprays it) and
scuffed rear bumper corners. Black trim era: black rubber, black plastic
grille, small black mirrors, body-colour bumpers with a black band.

Kept in its own file (kits.KITS imports KIT from here). The helpers are
kits.py's; the pop-up is the kei's (kit_p4_kei).
"""
import math

import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl

POPUP = (0.32, 0.58, 0.31, 0.67, 0.09)   # s0, s1, x0, x1, face height: a 0.36 x 0.09 face when up
POPUP_DEG = 21.0        # turned up on its rear edge the 0.26 m lid lifts its front edge 0.093 m: the face stands clear
CLUSTER_X = (0.40, 0.70)                  # a tail cluster is 0.30 wide (rear view, right side)
BARS = ((0.75, 0.80), (0.665, 0.715), (0.58, 0.63))   # top, middle, bottom bar: 5 cm tall, 3.5 cm gaps (0.22 tall)
TURN_X = 0.605          # the middle bar's amber end starts here
REVERSE_X = 0.495       # the bottom bar's white end reaches this far out
TAIL_PANEL = (0.72, 0.56, 0.81)           # the dark satin panel behind the clusters: half width, bottom, top
PLATES = {'plate_f': ('front', 0.33, 0.26, 0.055), 'plate_r': ('rear', 0.655, 0.26, 0.055)}   # 520 x 110, chin and tail
ARCH_BAND = 0.09        # a bolt-on arch reaches this far out from the arch edge
ARCH_PROUD = 0.06       # and stands this far off the 0.84 flank (0.90 over the arches: 1.80 over all)
ARCH_RIVETS = 14
DISC_R = 0.13           # 260 mm vented discs, all four
FLAP = (3.97, 0.66)     # fuel flap on the left rear quarter: s, y
DRIP_RAIL = (0.010, 0.014)
# No high brake lamp (era), no seat belt, no roll cage (Roy: none anywhere), no wing stock, no engine model.


# --------------------------------------------------------------------------
# Sheet decals and parts
# --------------------------------------------------------------------------
def _decal(ctx, d):
    D, part, body = ctx.D, ctx.part, ctx.body_tris
    mat, tag = d['mat'], d.get('tag')
    if mat in ('turn', 'tail', 'head_off'):
        return True                               # every lamp is a part of its own: fittings
    if tag in ('plate_recess', 'tail_panel', 'cluster'):
        return True                               # the plate brings its recess; the tail is built in fittings
    if tag == 'fstrip':                           # the black band across the chin, kept on the nose face
        P.decal(part('bumper_f_insert', bevel=0), D, body, {'view': 'front', 'rect': d['rect'], 'cell': 0.4}, 'plastic', 0.004)
        return True
    return False                                  # the slot grille and the rear bumper band: the common recipe


def _popup(ctx, sx, p):
    """A pop-up lamp, down (the kei's recipe): the lid lies flush on the
    wedge, the lamp face hangs under its front edge inside the nose. Turned
    up POPUP_DEG on its rear edge the face stands over the hood; the game
    lights the bowl before the lid is fully up. -> the bulb's centre when up."""
    nm = 'r' if sx > 0 else 'l'
    s0, s1 = p['s0'], p['s1']
    xa, xb = sorted((sx * p['x0'], sx * p['x1']))
    h = p['h']
    pod = ctx.part('popup_' + nm, parent='hinge_popup_' + nm, bevel=0)
    f0, f1 = ctx.on_top(xa, s0, 0.004), ctx.on_top(xb, s0, 0.004)
    r0, r1 = ctx.on_top(xa, s1, 0.004), ctx.on_top(xb, s1, 0.004)
    nrm = np.cross(f1 - f0, r0 - f0)
    nrm = nrm / np.linalg.norm(nrm) * (1.0 if nrm[1] > 0 else -1.0)
    fwd = (f0 + f1 - r0 - r1)
    fwd = fwd / np.linalg.norm(fwd)
    pod.add(P.facing([[f0, f1, r1, r0]], nrm)[0], 'paint', P.SKIN)             # the lid, body colour
    g = 0.006                                                                  # the dark line round it
    rim = [f0 + fwd * g + np.array([-g, 0, 0]), f1 + fwd * g + np.array([g, 0, 0]),
           r1 - fwd * g + np.array([g, 0, 0]), r0 - fwd * g + np.array([-g, 0, 0])]
    pod.add(P.facing([[q - nrm * 0.003 for q in rim]], nrm)[0], 'rubber')
    d0, d1 = f0 - nrm * h, f1 - nrm * h
    pod.add(P.facing([[f0, f1, d1, d0]], fwd)[0], 'plastic')                   # the lamp face, black
    inset = lambda q, e, u: q + (f1 - f0) / np.linalg.norm(f1 - f0) * e - nrm * u
    lens = [inset(f0, 0.016, 0.010), inset(f1, -0.016, 0.010), inset(f1, -0.016, h - 0.010), inset(f0, 0.016, h - 0.010)]
    pod.add(P.facing([[q + fwd * 0.003 for q in lens]], fwd)[0], 'glow_lens')
    c = (f0 + f1) / 2 - nrm * h / 2 + fwd * 0.005
    e = (f1 - f0) / np.linalg.norm(f1 - f0)
    rb = h * 0.36
    bulb = [c + e * rb * 1.6 * math.cos(2 * math.pi * k / 8) + nrm * rb * math.sin(2 * math.pi * k / 8) for k in range(8)]
    pod.add(P.facing([bulb], fwd)[0], 'glow_head')
    for a, b, r_ in ((f0, d0, r0), (f1, d1, r1)):                              # its cheeks
        pod.add(P.facing([[a, b, r_]], np.array([a[0] - (f0[0] + f1[0]) / 2, 0.0, 0.0]))[0], 'paint', P.SKIN)
    hinge = (r0 + r1) / 2
    ctx.info.setdefault('hinges', {})['hinge_popup_' + nm] = {
        'pos': [round(float(v), 4) for v in hinge], 'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': POPUP_DEG, 'panel': 'popup_' + nm}
    t = math.radians(POPUP_DEG)
    v = c - hinge
    return [float(hinge[0] + v[0]), float(hinge[1] + v[1] * math.cos(t) - v[2] * math.sin(t)),
            float(hinge[2] + v[1] * math.sin(t) + v[2] * math.cos(t))]


def _bolt_on(ctx, sx, s_ax, name):
    """One bolt-on overfender: a band ARCH_BAND wide round the arch, ARCH_PROUD
    off the flank. The inner wall from the arch edge out to the band is the
    polished rolled lip (chrome: the highlight line), the outer face and the
    top wall back to the skin are paint, ARCH_RIVETS dark rivet heads sit in a
    row along the face. It lies ON the skin (no cut), so the arch liner and
    the body's own rolled lip stay as they are."""
    D, z = ctx.D, ctx.z
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    yc = wh['r'] + wh.get('arch_lift', 0.0)
    view = 'right' if sx > 0 else 'left'
    part = ctx.part(name, bevel=0)
    r_in, r_out = Ra + 0.004, Ra + ARCH_BAND
    x_out = pl(D['hw'], s_ax) + ARCH_PROUD
    y_floor = pl(D['floor'], s_ax) + 0.04
    a0 = math.asin(max(-0.95, (y_floor - yc) / r_in))      # where the band meets the sill
    n = 12
    angs = [a0 + (math.pi - 2 * a0) * k / n for k in range(n + 1)]

    def skin(s, y):
        q = P.laid_on(ctx.body_tris, view, [(z(s), y)], 0.003)
        return None if q is None else np.asarray(q[0], float)

    rows = []
    for a in angs:
        si, yi = s_ax - r_in * math.cos(a), yc + r_in * math.sin(a)
        so, yo = s_ax - r_out * math.cos(a), yc + r_out * math.sin(a)
        ki, ko = skin(si, yi), skin(so, yo)
        if ki is None or ko is None:
            continue
        rows.append((ki, np.array([sx * x_out, yi, z(si)]), np.array([sx * x_out, yo, z(so)]), ko, a))
    side = np.array([sx, 0.0, 0.0])
    for A, B in zip(rows, rows[1:]):
        a_mid = 0.5 * (A[4] + B[4])
        radial = np.array([0.0, math.sin(a_mid), -math.cos(a_mid)])
        part.add(P.facing([[A[0], B[0], B[1], A[1]]], -radial)[0], 'chrome')              # the rolled lip
        part.add(P.facing([[A[1], B[1], B[2], A[2]]], side)[0], 'paint', P.SKIN)          # the outer face
        part.add(P.facing([[A[2], B[2], B[3], A[3]]], radial)[0], 'paint', P.SKIN)        # the top wall, back to the skin
    for row, back in ((rows[0], -1.0), (rows[-1], 1.0)):                                   # the two ends, at the sill
        part.add(P.facing([[row[0], row[1], row[2], row[3]]], np.array([0.0, -0.3, back]))[0], 'paint', P.SKIN)
    r_riv = 0.5 * (r_in + r_out) + 0.008
    for k in range(ARCH_RIVETS):
        a = angs[0] + 0.06 + (angs[-1] - angs[0] - 0.12) * k / (ARCH_RIVETS - 1)
        c = np.array([sx * x_out, yc + r_riv * math.sin(a), z(s_ax - r_riv * math.cos(a))])
        K.cyl(part, c, c + side * 0.004, 0.007, 4, 'under_paint', caps=(False, True))


def _primer_lip(ctx, name):
    """parts.add_arch_lips for one panel whose skin is paint_primer (it only
    rolls `paint`): every arch edge of the panel gets the LIP return into the
    well, in primer."""
    D = ctx.D
    part = ctx.parts.get(name)
    if part is None:
        return
    axles = fcar._axles(D)
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    zax = [fcar._s2z(D, s) for s in axles]
    yc = wh['r'] + wh.get('arch_lift', 0.0)

    def in_arch(p):
        s = p[2] + D['OHf'] + D['WB'] / 2.0
        return any(abs(s - sa) < Ra - 1e-4 for sa in axles) and P.on_curve(D, p, js=(3,), tol=3e-4) == 3             and p[1] > pl(D['floor'], s) + 0.003

    skin = [p for p, k, m in zip(part.polys, part.kind, part.mats) if k == P.SKIN and m == 'paint_primer']
    if not skin:
        return
    verts, loops = P.weld(skin)
    flag = np.array([in_arch(v) for v in verts])
    for a, b, _ in P.boundary_edges(loops):
        if not (flag[a] and flag[b]):
            continue
        A, B = verts[a], verts[b]
        sx = 1.0 if A[0] > 0 else -1.0
        A2, B2 = A - np.array([sx * P.LIP, 0, 0]), B - np.array([sx * P.LIP, 0, 0])
        mid = (A + B) / 2
        zc = min(zax, key=lambda v: abs(v - mid[2]))
        toward_axle = np.array([0.0, yc, zc]) - np.array([0.0, mid[1], mid[2]])
        part.add(P.facing([(A, B, B2, A2)], toward_axle)[0], 'paint_primer', P.SKIN)


def _sheet_part(ctx, p):
    D = ctx.D
    t = p['type']
    if t == 'mirrors':                            # small black mirrors on the doors
        pm = fcar.CarModel(D)
        fcar.add_part(pm, p)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            tri = np.array(tri)
            nm = 'l' if tri[:, 0].mean() < 0 else 'r'
            ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
        return True
    if t == 'popups':
        for sx, nm in ((1, 'r'), (-1, 'l')):
            ctx.lamps.setdefault('head', {})[nm] = _popup(ctx, sx, p)
        # the left hinge is the right one's mirror image to the last digit, as its pod is
        H = ctx.info['hinges']
        H['hinge_popup_l']['pos'] = [-H['hinge_popup_r']['pos'][0]] + H['hinge_popup_r']['pos'][1:]
        return True
    if t == 'flares':
        for ai, s_ax in enumerate(fcar._axles(D)):
            for sx, nm in ((1, 'r'), (-1, 'l')):
                _bolt_on(ctx, sx, s_ax, 'flare_%s%s' % ('f' if ai == 0 else 'r', nm))
        return True
    return False


# --------------------------------------------------------------------------
# The car's own parts
# --------------------------------------------------------------------------
def _fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R

    # ---- the nose: amber corner markers in the nose corners, each in a dark bezel (the pop-ups are sheet parts)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * 0.58, sx * 0.70))
        tf = part('turn_f' + nm, bevel=0)
        K.lay(ctx, tf, 'front', K.rect2(xa - 0.006, 0.414, xb + 0.006, 0.506), 'plastic', 0.003)
        K.lay(ctx, tf, 'front', K.rect2(xa, 0.42, xb, 0.50), 'glow_turn', 0.006)

    # ---- the tail: a dark satin panel, then a three-bar cluster a side. The
    # top bar is the running lamp, the middle bar the brake lamp with the amber
    # blinker as its outer end, the bottom bar the running lamp again with the
    # white reversing lamp as its inner end. No high brake lamp (era).
    hw_p, py0, py1 = TAIL_PANEL
    tp = part('tail_panel', bevel=0)
    K.lay(ctx, tp, 'rear', K.rect2(-hw_p, py0, hw_p, py1), 'plastic', 0.003)
    (t0, t1), (m0, m1), (b0, b1) = BARS
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * CLUSTER_X[0], sx * CLUSTER_X[1]))
        tail = part('tail_' + nm, bevel=0)
        q = K.lay(ctx, tail, 'rear', K.rect2(xa, t0, xb, t1), 'glow_tail', 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = K.lamp_centre(q)
        xr0, xr1 = sorted((sx * REVERSE_X, sx * CLUSTER_X[1]))
        K.lay(ctx, tail, 'rear', K.rect2(xr0, b0, xr1, b1), 'glow_tail', 0.006)
        xm0, xm1 = sorted((sx * CLUSTER_X[0], sx * TURN_X))
        K.lay(ctx, part('brake_' + nm, bevel=0), 'rear', K.rect2(xm0, m0, xm1, m1), 'glow_brake', 0.006)
        xt0, xt1 = sorted((sx * (TURN_X + 0.005), sx * CLUSTER_X[1]))
        K.lay(ctx, part('turn_r' + nm, bevel=0), 'rear', K.rect2(xt0, m0, xt1, m1), 'glow_turn', 0.006)
        xv0, xv1 = sorted((sx * CLUSTER_X[0], sx * (REVERSE_X - 0.005)))
        K.lay(ctx, part('reverse_' + nm, bevel=0), 'rear', K.rect2(xv0, b0, xv1, b1), 'glow_reverse', 0.006)
    # the lamp over the rear plate
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, pl_y + 0.022)], 0.026)
    if c is not None:
        lamp = part('plate_lamp', bevel=0)
        P.obox(lamp, c[0], (0.12, 0.018, 0.024), np.eye(3), 'plastic', {'-y': 'glow_lens'})

    # ---- the thin drip rail along each roof edge (polished, with the arch lips the car's highlight line)
    corner = lambda s, sx: np.array([sx * fcar.half_section(D, s)[0][8][0], fcar.half_section(D, s)[0][8][1], z(s)])
    f0, r0 = cab['W'] + 0.03, cab['R'] - 0.03
    for sx, nm in ((1, 'r'), (-1, 'l')):
        a, b = corner(f0, sx), corner(r0, sx)
        rail = part('drip_rail_' + nm, bevel=0)
        P.obox(rail, (a + b) / 2 + np.array([0, DRIP_RAIL[0] * 0.5, 0]), (np.linalg.norm(b - a), DRIP_RAIL[0], DRIP_RAIL[1]),
               P.frame_basis(b - a, (0, 1, 0)), 'chrome')

    # ---- brakes: a generic single-pot caliper, black, on each upright (the vented disc is in the wheel's mesh)
    for ai, tagf in ((0, 'f'), (1, 'r')):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        for sx, nm in ((1, 'r'), (-1, 'l')):
            cal = part('caliper_' + tagf + nm, bevel=0)
            hub_x = sx * (wh['track'] / 2 - tw / 2 - 0.018)
            P.obox(cal, (hub_x, r_w + DISC_R - 0.035, z(axles[ai])), (0.04, 0.07, 0.12), np.eye(3), 'plastic')

    # ---- what shows of the running gear in the wheel wells: a strut and its
    # lower arm in front; the solid rear axle's tube, a trailing link and a
    # shock behind. The diff cover, the tank and the front subframe are anchors.
    for sx, nm in ((1, 'r'), (-1, 'l')):
        sf = part('susp_f' + nm, bevel=0)
        K.cyl(sf, (sx * 0.62, r_w + 0.02, z(axles[0])), (sx * 0.60, r_w + 0.36, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        K.cyl(sf, (sx * 0.34, r_w - 0.07, z(axles[0])), (sx * 0.63, r_w - 0.05, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))
        sr = part('susp_r' + nm, bevel=0)
        K.cyl(sr, (sx * 0.28, r_w - 0.01, z(axles[1])), (sx * 0.63, r_w - 0.01, z(axles[1])), 0.036, 6, 'steel', caps=(False, True))
        K.cyl(sr, (sx * 0.56, r_w - 0.03, z(axles[1]) - 0.46), (sx * 0.56, r_w - 0.01, z(axles[1]) - 0.04), 0.018, 4, 'steel', caps=(False, False))
        K.cyl(sr, (sx * 0.60, r_w + 0.03, z(axles[1]) + 0.05), (sx * 0.58, r_w + 0.36, z(axles[1]) + 0.07), 0.025, 6, 'steel', caps=(False, False))

    # ---- the primer fender's rolled arch lip: parts.add_arch_lips only rolls painted skin, and this
    # fender is primer, so its 18 mm return into the well is built here the same way
    _primer_lip(ctx, 'fender_fl')

    # ---- fuel flap on the left rear quarter, behind the arch (the tank is behind the axle)
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])

    # ---- under the hood: a dark bay floor and the radiator. No engine model yet (none: the brief).
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    P.obox(part('bay_floor', bevel=0), (0.0, 0.40, z(hood_mid)), (1.20, 0.02, cab['A'] - R['nose_s'] - 0.10), np.eye(3), 'rubber')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.52, z(R['nose_s'] + 0.12)), (0.58, 0.22, 0.05), np.eye(3), 'rubber')  # on the floor, clear of the pop-ups (part_fit)


# --------------------------------------------------------------------------
# Wheels: deep dish, bronze face, polished lip, five flat spokes well inboard
# --------------------------------------------------------------------------
def _dish_face(D, part, sx, tw, n=16):
    """The sheet wheel is a closed drum with the dish painted on. Open it: the
    sidewall, a wide polished lip (chrome), a deep barrel behind it, five flat
    bronze spokes and the hub well inboard, a chrome centre cap, and the disc
    seen between the spokes. Hub at the origin."""
    wh = D['wheel']
    r = wh['r']
    Rr = r * wh.get('rim_ratio', 0.72)
    ng, frac, r0, _ = fcar.RIM_GAPS['dish']
    lip_in = 0.80            # the lip reaches in to 0.80 of the rim radius: a deep dish
    xo = sx * tw / 2
    out = np.array([sx, 0.0, 0.0])
    keep = []
    for i, (poly, mat) in enumerate(zip(part.polys, part.mats)):
        cap = mat == 'rubber' and np.abs(poly[:, 0] - xo).max() < 1e-6
        if not cap and mat not in ('rim', 'rim_gap', 'rim_face', 'chrome', 'steel'):
            keep.append(i)
    for name in ('polys', 'mats', 'kind', 'shut'):
        setattr(part, name, [getattr(part, name)[i] for i in keep])

    def pt(rad, a, dx):
        return np.array([xo + sx * dx, rad * math.sin(a), rad * math.cos(a)])

    def ring(ra, rb, dxa, dxb, mat, m=n, face=None):
        for k in range(m):
            a0, a1 = 2 * math.pi * (k + 0.5) / m, 2 * math.pi * (k + 1.5) / m
            q = (pt(ra, a0, dxa), pt(ra, a1, dxa), pt(rb, a1, dxb), pt(rb, a0, dxb))
            want = out if face is None else -(q[0] + q[1]) * np.array([0.0, 1.0, 1.0])
            part.add(P.facing([q], want)[0], mat)

    def disc(rad, dx, mat, m=10):
        part.add(P.facing([[pt(rad, 2 * math.pi * k / m, dx) for k in range(m)]], out)[0], mat)

    depth, spoke_dx = -0.07, -0.046
    ring(r, Rr, 0.0, 0.0, 'rubber')                             # the sidewall
    ring(Rr, Rr * lip_in, 0.004, 0.004, 'chrome')               # the polished lip
    ring(Rr * lip_in, Rr * lip_in, 0.004, depth, 'rubber', m=12, face='in')   # the barrel
    disc(Rr * lip_in, depth, 'under_paint', 12)
    for k in range(ng):                                         # five flat spokes, well inboard
        a0 = 2 * math.pi * k / ng + (1 - frac) * math.pi / ng + 2 * math.pi / ng * frac
        a1 = 2 * math.pi * (k + 1) / ng + (1 - frac) * math.pi / ng
        grow = 0.5 * (a1 - a0) * 0.9
        q = (pt(Rr * r0 * 0.9, a0 - grow, spoke_dx), pt(Rr * lip_in * 1.02, a0, spoke_dx - 0.004),
             pt(Rr * lip_in * 1.02, a1, spoke_dx - 0.004), pt(Rr * r0 * 0.9, a1 + grow, spoke_dx))
        part.add(P.facing([q], out)[0], 'rim')
    disc(Rr * r0, spoke_dx, 'rim', 2 * ng)                      # the hub face
    disc(Rr * 0.17, spoke_dx + 0.004, 'chrome', 8)              # the centre cap
    disc(DISC_R, depth + 0.012, 'steel', 12)                    # the disc, seen between the spokes
    disc(DISC_R * 0.45, depth + 0.022, 'steel', 8)


def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    _dish_face(D, part, sx, tw)
    # a vented disc: two plates with the air gap between them, and the hat (the muscle car's recipe)
    x0 = -sx * tw / 2
    K.cyl(part, (x0 - sx * 0.010, 0, 0), (x0 - sx * 0.018, 0, 0), DISC_R, 12, 'steel')
    K.cyl(part, (x0 - sx * 0.018, 0, 0), (x0 - sx * 0.026, 0, 0), DISC_R * 0.86, 8, 'plastic', caps=(False, False))
    K.cyl(part, (x0 - sx * 0.026, 0, 0), (x0 - sx * 0.034, 0, 0), DISC_R, 12, 'steel')
    K.cyl(part, (x0, 0, 0), (x0 - sx * 0.034, 0, 0), DISC_R * 0.45, 8, 'steel', caps=(False, False))


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    cab = D['cabin']
    axles = fcar._axles(D)
    r = D['wheel']['r']
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['bay_engine'] = {'pos': [0.0, 0.50, z(hood_mid + 0.10)]}     # the longitudinal four
    A['bay_radiator'] = {'pos': [0.0, 0.48, z(R['nose_s'] + 0.12)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A['diff'] = {'pos': [0.0, r - 0.01, z(axles[1])]}              # the solid axle's finned cover
    A['tank'] = {'pos': [0.0, 0.26, z(axles[1] + 0.45)]}            # behind the axle
    A['subframe_f'] = {'pos': [0.0, 0.20, z(axles[0])]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'regions': {
        'nose_s': 0.28,                    # the front bumper ends ahead of the pop-up lids
        'hood_hw': 0.30,                   # the hood runs between the pop-ups, as on the kei
        'trunk_s0': 3.48, 'trunk_s1': 4.20, 'trunk_hw': 0.64,   # the flat deck lid
        'tail_s': 3.90, 'tail_y': 0.46,    # the rear bumper, behind the arch and under the tail panel
    },
    'merge_flat': True,
    'plates': PLATES,
    # the one primer-grey fender (a paint-mask panel until the body shop resprays it), and the scuffed rear corners
    'panel_mats': {'fender_fl': 'paint_primer'},
    'paint_regions': [(4.12, 4.30, 0.30, 0.46, 'primer')],
    'asymmetric': {
        'fender_fl': 'the one primer-grey front fender (the sheet): the right one is painted',
        'fender_fr': 'the painted right front fender: its twin is the primer one, so neither is a mirror image',
        'fuel_recess': 'one filler, on the left rear quarter',
        'fuel_flap': 'one filler, on the left rear quarter',
        'exhaust': 'one big oval tip, on the right',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'vented disc 260 mm, single-pot caliper', 'rear': 'vented disc 260 mm, single-pot caliper'},
              'brake_lamps': 2, 'third_brake': 0, 'third_brake_note': 'none, era', 'reverse': 2,
              'blinkers_front': 2, 'blinkers_rear': 2, 'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1,
              'wipers': 2, 'fuel_flap': 1, 'headlamps': 'slim pop-ups, modelled down on hinge_popup_l/r', 'condition': 0.3},
    'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
