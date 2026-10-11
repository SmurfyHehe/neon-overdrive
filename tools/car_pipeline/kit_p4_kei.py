"""P4, the kei roadster (Pilar's car): what it adds to the common parts recipe.

Mid-engined, rear-drive, no roof, sheet p4_kei (Roy 317-320). The first open
car in the pipeline. The fleet loft already leaves the cockpit open (a tub:
inner walls and a floor); what the kit does about it:

    the screen       the loft's glass wedge is the windscreen, front and back
                     face (no backlight); its header and A-pillars are the one
                     silver line on the car
    the side glass   the short pane beside the screen is fixed to the frame,
                     it does not swing with the door
    the cockpit rim  a black rubber seal round the opening

Then two smooth headrest humps (no hoop, no bar: Roy 1179), pop-up lamps
modelled DOWN, each on its own hinge so they can be raised, a side intake cut
into each rear quarter (a real recess with a lip and a slatted floor), two
oval tail lamps with the brake lamp as their core, one reversing lamp in the
bumper centre (era), a third brake lamp on the deck's rear edge, discs in
front and drums behind real spokes.
"""
import math

import numpy as np

import car as fcar
import parts as P
from geom import pl
from kit_p2_hothatch import alloy_face
from kits import disc_brake, drum, ellipse, fuel_flap, lay, lay_ring, rect2

INTAKE = (2.20, 2.44, 0.49, 0.63)   # s0, s1, y0, y1 of the side intake's mouth
INTAKE_DEPTH = 0.04
POPUP_DEG = 18.0       # how far a pod turns up on its rear edge: the lens face then stands 8 cm over the hood
DISC_R = 0.115         # 230 mm discs in front
DRUM_R = 0.09          # 180 mm drums at the rear
# a hump along the car: (s, top y, half width as a share of the full one)
HUMP = [(0.0, 0.84, 0.92), (0.035, 0.965, 1.0), (0.11, 1.0, 1.0), (0.21, 0.985, 0.96), (0.33, 0.905, 0.82), (0.45, 0.80, 0.55)]


def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    alloy_face(D, part, sx, tw, DISC_R if axle == 0 else DRUM_R)
    if axle == 0:
        disc_brake(part, sx, tw, r=DISC_R)    # the caliper is a body part: it must not turn with the wheel
    else:
        drum(part, sx, tw, r=DRUM_R)


def _cuts(D, R, z, cut):
    """The side intakes: a hole in each rear quarter (the recess is built in fittings)."""
    s0, s1, y0, y1 = INTAKE
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 4) & (ps.col(0) <= 5))(sx)
        cut('intake_' + nm, [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((0, 1, 0), y0), ((0, -1, 0), -y1)], side, False, [True] * 4)
    return ['intake_r', 'intake_l']


def _decal(ctx, d):
    mat, tag = d['mat'], d.get('tag')
    if mat in ('turn', 'tail', 'head_off'):
        return True                               # every lamp is a part of its own: fittings
    if tag in ('plate_recess', 'intake'):
        return True                               # the plate brings its recess; the intake is cut in
    return False                                  # the slot grille and the rear bumper strip: the common recipe


def _hump(ctx, sx, p):
    """One smooth headrest fairing: a rounded front behind the seat back, then
    it runs down and in to nothing on the engine lid."""
    D, z = ctx.D, ctx.z
    part = ctx.part('hump_' + ('r' if sx > 0 else 'l'), bevel=0)
    s0, xc, hw = p['s0'], sx * p['x'], p.get('w', 0.26) / 2
    scale = (p['s1'] - s0) / HUMP[-1][0]
    top_scale = (p['h'] - 0.80) / 0.20
    n = 6
    rings = []
    for ds, top, wk in HUMP:
        s = s0 + ds * scale
        base = pl(D['belt'], s) + 0.004
        top = 0.80 + (top - 0.80) * top_scale
        ring = []
        for k in range(n + 1):
            a = math.pi * k / n
            ring.append(np.array([xc + sx * hw * wk * math.cos(a), base + max(0.0, top - base) * math.sin(a) ** 0.8, z(s)]))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            q = (a[k], a[k + 1], b[k + 1], b[k])
            out = (a[k] + a[k + 1]) / 2 - np.array([xc, a[0][1], a[k][2]])
            part.add(P.facing([q], out + np.array([0.0, 0.02, 0.0]))[0], 'paint', P.SKIN)
    part.add(P.facing([rings[0]], (0, 0, -1))[0], 'paint', P.SKIN)             # the front, behind the headrest
    under = [rings[0][0], rings[0][-1], rings[2][-1], rings[2][0]]            # its underside, over the cockpit's rear
    part.add(P.facing([under], (0, -1, 0))[0], 'rubber')


def _popup(ctx, sx, p):
    """A pop-up lamp, down: the lid lies flush on the hood, the lamp face hangs
    under it inside the nose. Turned up POPUP_DEG on its rear edge, the face
    stands over the hood. -> the bulb's centre when up."""
    nm = 'r' if sx > 0 else 'l'
    s0, s1 = p['s0'], p['s1']
    xa, xb = sorted((sx * p['x0'], sx * p['x1']))
    h = p['h']
    pod = ctx.part('popup_' + nm, parent='hinge_popup_' + nm, bevel=0)
    f0, f1 = ctx.on_top(xa, s0, 0.004), ctx.on_top(xb, s0, 0.004)
    r0, r1 = ctx.on_top(xa, s1, 0.004), ctx.on_top(xb, s1, 0.004)
    nrm = np.cross(f1 - f0, r0 - f0)
    nrm = nrm / np.linalg.norm(nrm) * (1.0 if np.cross(f1 - f0, r0 - f0)[1] > 0 else -1.0)
    fwd = (f0 + f1 - r0 - r1)
    fwd = fwd / np.linalg.norm(fwd)
    pod.add(P.facing([[f0, f1, r1, r0]], nrm)[0], 'paint', P.SKIN)             # the lid
    g = 0.006                                                                  # the dark line round it
    rim = [f0 + fwd * g + np.array([-g, 0, 0]), f1 + fwd * g + np.array([g, 0, 0]),
           r1 - fwd * g + np.array([g, 0, 0]), r0 - fwd * g + np.array([-g, 0, 0])]
    pod.add(P.facing([[q - nrm * 0.003 for q in rim]], nrm)[0], 'rubber')
    d0, d1 = f0 - nrm * h, f1 - nrm * h
    pod.add(P.facing([[f0, f1, d1, d0]], fwd)[0], 'plastic')                   # the lamp face
    inset = lambda q, e, u: q + (f1 - f0) / np.linalg.norm(f1 - f0) * e - nrm * u
    lens = [inset(f0, 0.02, 0.012), inset(f1, -0.02, 0.012), inset(f1, -0.02, h - 0.012), inset(f0, 0.02, h - 0.012)]
    pod.add(P.facing([[q + fwd * 0.003 for q in lens]], fwd)[0], 'glow_lens')
    c = (f0 + f1) / 2 - nrm * h / 2 + fwd * 0.005
    e = (f1 - f0) / np.linalg.norm(f1 - f0)
    bulb = [c + e * 0.024 * math.cos(2 * math.pi * k / 8) + nrm * 0.024 * math.sin(2 * math.pi * k / 8) for k in range(8)]
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


def _sheet_part(ctx, p):
    D = ctx.D
    t = p['type']
    if t == 'mirrors':
        pm = fcar.CarModel(D)
        fcar.add_part(pm, p)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            tri = np.array(tri)
            nm = 'l' if tri[:, 0].mean() < 0 else 'r'
            ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
        return True
    if t == 'rollhoops':
        for sx in (1, -1):
            _hump(ctx, sx, p)
        return True
    if t == 'popups':
        for sx, nm in ((1, 'r'), (-1, 'l')):
            ctx.lamps.setdefault('head', {})[nm] = _popup(ctx, sx, p)
        # the left hinge is the right one's mirror image to the last digit, as its pod is
        H = ctx.info['hinges']
        H['hinge_popup_l']['pos'] = [-H['hinge_popup_r']['pos'][0]] + H['hinge_popup_r']['pos'][1:]
        return True
    if t == 'flares':                             # the arch lips: a slim proud band round each arch
        pm = fcar.CarModel(D)
        fcar.add_part(pm, p)
        lips = ctx.part('arch_lips', bevel=0)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            lips.add(np.array(tri), P.MATMAP.get(mm, mm), P.SKIN)
        return True
    return False


def _intake(ctx, sx):
    """The recess behind a side intake's mouth: four walls, a dark floor with
    slats across it, and a body-colour lip round the mouth."""
    z = ctx.z
    nm = 'r' if sx > 0 else 'l'
    view = 'right' if sx > 0 else 'left'
    part = ctx.parts.get('intake_' + nm)
    if part is None:
        return
    part.polys, part.mats, part.kind, part.shut = [], [], [], []      # the cut-out skin goes; the hole stays
    part.bevel = 0
    s0, s1, y0, y1 = INTAKE
    e = P.GAP / 2
    mouth = rect2(z(s0) - e, y0 - e, z(s1) + e, y1 + e)
    outer = np.array(P.laid_on(ctx.body_tris, view, mouth, 0.0))
    inner = outer - np.array([sx * INTAKE_DEPTH, 0.0, 0.0])
    cen = inner.mean(axis=0)
    out = np.array([sx, 0.0, 0.0])
    part.add(P.facing([inner], out)[0], 'rubber')
    for k in range(4):
        j = (k + 1) % 4
        mid = (outer[k] + outer[j]) / 2
        part.add(P.facing([[outer[k], outer[j], inner[j], inner[k]]], cen - mid)[0], 'under_paint')
    for k in range(1, 4):                         # the slats
        y = y0 + (y1 - y0) * k / 4
        q = np.array(P.laid_on(ctx.body_tris, view, rect2(z(s0) + 0.01, y - 0.006, z(s1) - 0.01, y + 0.006), 0.0)) - out * (INTAKE_DEPTH - 0.008)
        part.add(P.facing([q], out)[0], 'plastic')
    lip = ctx.part('intake_lip_' + nm, bevel=0)
    w = 0.014
    for a, b, c, d in ((s0 - w, y1, s1 + w, y1 + w), (s0 - w, y0 - w, s1 + w, y0), (s0 - w, y0, s0, y1), (s1, y0, s1 + w, y1)):
        lay(ctx, lip, view, rect2(z(a), b, z(c), d), 'paint', 0.006)


def _fittings(ctx):
    D, part, parts, z = ctx.D, ctx.part, ctx.parts, ctx.z
    cab = D['cabin']
    L = D['L']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    s_of = lambda p: p[:, 2] + D['OHf'] + D['WB'] / 2.0

    # ---- the open top
    # the back face of the screen's glass wedge is the windscreen too: an open car has no backlight
    for a, b in (('glass_backlight', 'glass_windshield'), ('seal_backlight', 'seal_windshield')):
        if a in parts and b in parts:
            src, dst = parts.pop(a), parts[b]
            for name in ('polys', 'mats', 'kind', 'shut'):
                getattr(dst, name).extend(getattr(src, name))
    # the one silver line: the screen's header and its A-pillars (the sheet: metallic 0.8)
    body = parts['body']
    for i, poly in enumerate(body.polys):
        s = s_of(poly)
        if body.mats[i] == 'paint' and body.kind[i] == P.SKIN and s.min() > cab['W'] - 1e-4 and s.max() < cab['R'] + 1e-4 and poly[:, 1].min() > 0.9:
            body.mats[i] = 'chrome'
    for nm in ('l', 'r'):
        if 'pillar_a_' + nm in parts:
            parts['pillar_a_' + nm].mats = ['chrome'] * len(parts['pillar_a_' + nm].mats)
    # a black rubber seal round the cockpit opening
    seal = part('seal_cockpit', bevel=0)
    o = D['open'][0]
    ss = [o['s0'] + 0.013] + [s for s in fcar.stations(D) if o['s0'] + 0.02 < s < o['s1'] - 0.02] + [o['s1'] - 0.013]
    edge = lambda s, sx: np.array([sx * fcar.half_section(D, s)[0][8][0], fcar.half_section(D, s)[0][8][1] + 0.003, z(s)])
    up = np.array([0.0, 1.0, 0.0])
    for sx in (1, -1):
        for a, b in zip(ss, ss[1:]):
            A, B = edge(a, sx), edge(b, sx)
            w = np.array([sx * 0.016, 0.0, 0.0])
            seal.add(P.facing([[A, B, B + w, A + w]], up)[0], 'rubber')
    for s_, d in ((ss[0], -0.016), (ss[-1], 0.016)):
        A, B = edge(s_, -1), edge(s_, 1)
        w = np.array([0.0, 0.0, d])
        seal.add(P.facing([[A, B, B + w, A + w]], up)[0], 'rubber')

    for sx, nm in ((1, 'r'), (-1, 'l')):
        _intake(ctx, sx)
        # amber turn lamps at the ends of the slot grille
        xa, xb = sorted((sx * 0.26, sx * 0.33))
        lay(ctx, part('turn_f' + nm, bevel=0), 'front', rect2(xa, 0.29, xb, 0.35), 'glow_turn', 0.006)
        # the oval tail lamp: a dark bezel, the running lamp, the brake lamp as its core
        c = (sx * 0.48, 0.66)
        tail = part('tail_' + nm, bevel=0)
        lay_ring(ctx, tail, 'rear', c, (0.098, 0.058), (0.088, 0.048), 'plastic', 0.007)
        q = lay(ctx, tail, 'rear', ellipse(c[0], c[1], 0.09, 0.05), 'glow_tail', 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = [float(v) for v in np.asarray(q).mean(axis=0)]
        lay(ctx, part('brake_' + nm, bevel=0), 'rear', ellipse(c[0], c[1], 0.05, 0.028, 10), 'glow_brake', 0.0075)
        # a small amber lamp under each oval
        xa, xb = sorted((sx * 0.42, sx * 0.54))
        lay(ctx, part('turn_r' + nm, bevel=0), 'rear', rect2(xa, 0.54, xb, 0.585), 'glow_turn', 0.006)
        # front brakes: a single-pot caliper on the upright (the disc is in the wheel's mesh)
        hub_x = sx * (wh['track'] / 2 - wh['w'] / 2 - 0.018)
        P.obox(part('caliper_f' + nm, bevel=0), (hub_x, r_w + 0.085, z(axles[0])), (0.03, 0.06, 0.10), np.eye(3), 'plastic')

    # one reversing lamp, a 60 mm round in the bumper centre (era)
    rv = part('reverse_c', bevel=0)
    lay_ring(ctx, rv, 'rear', (0.0, 0.40), (0.038, 0.038), (0.03, 0.03), 'plastic', 0.007, 10)
    lay(ctx, rv, 'rear', ellipse(0.0, 0.40, 0.03, 0.03, 10), 'glow_reverse', 0.006)
    # the third brake lamp: a strip in a low pod on the deck's rear edge, behind the engine lid
    base = ctx.on_top(0.0, 3.19)
    if base is not None:
        P.obox(part('brake_c', bevel=0), base + np.array([0.0, 0.012, 0.0]), (0.30, 0.03, 0.03), np.eye(3), 'plastic', {'+z': 'glow_brake'})
    # the plate lamp over the rear plate
    lamp = part('plate_lamp', bevel=0)
    lay(ctx, lamp, 'rear', rect2(-0.11, 0.722, 0.11, 0.74), 'plastic', 0.012)
    lay(ctx, lamp, 'rear', rect2(-0.09, 0.724, 0.09, 0.731), 'glow_lens', 0.0135)

    # fuel flap on the right rear quarter, above and behind the side intake
    fuel_flap(ctx, 1, 2.63, 0.69, hw=0.055, hh=0.045)

    # under the lids: a dark floor each (no engine model yet: engine bays are the coupe's first)
    bay = part('bay_floor', bevel=0)
    R = ctx.R
    for s0, s1, x, y in ((R['nose_s'] + 0.02, cab['A'] - 0.02, R['hood_hw'] + 0.03, 0.42),
                         (R['trunk_s0'] - 0.02, R['trunk_s1'] + 0.02, R['trunk_hw'] + 0.03, 0.52)):
        bay.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, y, z(s1)), (-x, y, z(s1))]], (0, 1, 0))[0], 'under_paint')


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    A['bay_engine'] = {'pos': [0.0, 0.50, z(2.72)]}          # mid-engined: ahead of the rear axle, under the lid
    A['tank'] = {'pos': [0.0, 0.30, z(2.30)]}
    for name in ('bay_turbo', 'bay_intercooler'):
        A.pop(name, None)                                    # no car comes with a turbo
    A['bay_radiator'] = {'pos': [0.0, 0.34, z(0.14)]}


KIT = {
    'regions': {
        'nose_s': 0.24,                    # the bumper ends at the front arch
        'hood_hw': 0.29,                   # the short front lid, between the pop-ups
        'trunk_s0': 2.42, 'trunk_s1': 3.12, 'trunk_hw': 0.40,   # the engine lid, behind the humps
        'tail_s': 3.14, 'tail_y': 0.36,    # the rear bumper, behind the arch and under the lamps
    },
    'merge_flat': True,
    'open_top': True,                      # no roof: see the top of this file
    'antenna_s': 2.50,                     # the mast on the left of the rear deck
    'hinge_of': {'glass_door_l': None, 'glass_door_r': None},   # the short side pane is fixed to the screen frame
    'plates': {'plate_f': ('front', 0.42, 0.26, 0.055), 'plate_r': ('rear', 0.66, 0.26, 0.055)},
    'asymmetric': {
        'fuel_recess': 'one filler, on the right rear quarter',
        'fuel_flap': 'one filler, on the right rear quarter',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'disc 230 mm, single-pot caliper', 'rear': 'drum 180 mm'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 1, 'reverse_note': 'one centre reverse lamp, era',
              'blinkers_front': 2, 'blinkers_rear': 2, 'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1,
              'wipers': 2, 'fuel_flap': 1, 'headlamps': 'pop-ups, modelled down on hinge_popup_l/r', 'condition': 0.4},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
