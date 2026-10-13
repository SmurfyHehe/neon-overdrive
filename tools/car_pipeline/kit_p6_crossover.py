"""P6, the crossover (Brannock Cairn): what it adds to the common parts recipe.

A lifted five-door hatch standing on thick black riveted cladding, a roof
rack on top, tall glass, a flat hood (sheet p6_crossover, Roy 324-327). Rear
drive with 265 rear tyres since the transmissions decision; the body is the
same 4.35 x 1.84 x 1.61 the game collides with (the sheet's 4.30 is not
applied: dimensions stay as CarSpec and NpcCarBuilder have them).

  doors      four: the front pair from the common recipe, the rear pair cut
             here (`door_rr/rl`, each with its own glass and seal), meeting the
             front door on one shut line; every door hinges just outboard of
             its skin so its front edge swings clear of what is ahead of it
  tailgate   one hatch cut out of the deck and the tail face, hinged at the
             roof's rear edge (its top shut line): glass, plate, plate lamp,
             handle, rear wiper, spoiler and high brake lamp go up with it
  cladding   bolted-on black arch pieces 4.5 cm proud of the flat flank
             (0.92 over the arches: the 1.84 overall width), a rolled lip into
             the well, a top wall back to the skin, rivets on the arch edge,
             and a sill panel joining them under the doors
  lamps      stacked twins in front (driving lamp over an amber blinker),
             split lamps behind (upper on the body corner with the brake core
             and a wrap up the pillar, amber blinker inboard; lower in the
             bumper with the reversing lamp inboard), a high brake lamp in the
             spoiler's trailing edge, a lamp over the rear plate
  rack       silver rails, two black crossbars poking past the roof edge
  bay        a flat four under the hood (low and wide), its intake, the
             radiator, the battery; skid plate under the nose (lifted: the
             low camera sees it); discs on all four behind five dark spokes

Kept in its own file so the car rebuilds can run side by side; kits.KITS
imports KIT from here. The helpers are kits.py's; the spoked wheel face is
the hot hatch's.
"""
import math

import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl
from kit_p2_hothatch import alloy_face

DOOR_S0 = 1.40          # front door: behind the front cladding's top (a black sail with the mirror ahead of it)
RDOOR = (2.36, 3.07)    # rear door: from the front door's rear edge to the thin pillar ahead of the quarter glass
WIPER_PIVOT = 0.025     # the wiper arms pivot this far up the glass from its base (behind the hood)
A_TUCK = 0.02           # the front door glass stops this far in from the windscreen's edge (the pillar strip covers 0.04)
HINGE_OUT = 0.01        # every door hinges this far outboard of its skin, so its front edge swings clear
HATCH_HW = 0.585        # the tailgate reaches this far from the centre line; the upper lamps stand outboard of it
HATCH_Y0 = 0.60         # and down to the top of the bumper
SPOILER_IN = 0.006      # the roof spoiler starts this far behind the tailgate's top shut line, so all of it rides on the tailgate
CLAD_X = 0.92           # the cladding's outer face (4.5 cm proud of the 0.875 flank; the car's 1.84 width)
CLAD_BAND = 0.11        # it reaches this far out from the arch edge
CLAD_RIVETS = 9
SILL = (0.27, 0.50, 0.905)   # the sill panel: bottom, top, outer face (a little less proud than the arches)
HEAD = (0.505, 0.81, 0.695, 0.91)    # the upper (driving) lamp of a stack, right side, front view
TURN_F = (0.505, 0.69, 0.695, 0.79)  # the amber lamp under it
UPPER = (0.61, 0.85, 0.78, 0.97)     # the upper rear lamp on the body corner, right side, rear view
UPPER_TURN = 0.67                    # its inboard end up to here is the amber blinker
WRAP = (0.72, 0.975, 0.77, 1.04)     # its wrap up the D-pillar
BRAKE = (0.69, 0.875, 0.765, 0.945)   # the brake core inside the running lamp
LOWER = (0.58, 0.42, 0.80, 0.54)     # the lower rear lamp in the bumper
LOWER_REV = 0.655                    # its inboard end up to here is the reversing lamp
DISC_F, DISC_R = 0.158, 0.15         # 316 / 300 mm vented discs (the sheet)
FLAP = (3.36, 0.94)                  # fuel flap on the left rear quarter, over the rear cladding: s, y
MIRROR_S = 1.50                      # the door mirrors, on the doors (behind the sail)
PLATES = {'plate_f': ('front', 0.56, 0.26, 0.055), 'plate_r': ('rear', 0.69, 0.26, 0.055)}


def _arch(D):
    wh = D['wheel']
    return wh['r'] + wh.get('arch_gap', 0.03), wh['r'] + wh.get('arch_lift', 0.0)


# --------------------------------------------------------------------------
# Panels
# --------------------------------------------------------------------------
def _cuts(D, R, z, cut):
    """The rear doors (one shut line behind the front door) and the tailgate
    (the deck behind the glass and the tail face down to the bumper)."""
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 3) & (ps.col(0) <= 7))(sx)
        cut('door_r' + nm, [((0, 0, 1), z(RDOOR[0])), ((0, 0, -1), -z(RDOOR[1])), ((0, 1, 0), R['door_y0'])], side, True)
    rear = lambda ps: ((ps.col(0) >= 8) & ~ps.mat_is('glass')) | (ps.col(0) == -2)
    cut('hatch', [((0, 0, 1), z(D['cabin']['C'])), ((1, 0, 0), -HATCH_HW), ((-1, 0, 0), -HATCH_HW), ((0, 1, 0), HATCH_Y0)], rear, True)
    return ['door_rr', 'door_rl', 'hatch']


def _decal(ctx, d):
    D, part, body = ctx.D, ctx.part, ctx.body_tris
    mat, view, tag = d['mat'], d['view'], d.get('tag')
    if mat in ('head', 'turn', 'tail'):
        return True                               # every lamp is a part of its own: fittings
    if mat == 'trim' and view == 'rear':
        return True                               # the rear plate brings its own recess, on the tailgate
    if mat == 'chrome':
        # the silver skid strips under the front mouth and across the rear bumper
        name = 'skid_strip_f' if view == 'front' else 'skid_strip_r'
        P.decal(part(name, bevel=0), D, body, {'view': view, 'rect': d['rect'], 'cell': 0.3}, 'chrome', 0.005)
        return True
    return False                                  # the slot grille and the bumper mouth: the common recipe


def _sheet_part(ctx, p):
    D, z = ctx.D, ctx.z
    t = p['type']
    if t == 'mirrors':
        # on the doors, behind the sail, so they open with them
        pm = fcar.CarModel(D)
        fcar.add_part(pm, dict(p, s=MIRROR_S))
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            tri = np.array(tri)
            nm = 'l' if tri[:, 0].mean() < 0 else 'r'
            ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
        return True
    if t == 'flares':
        for ai, s_ax in enumerate(fcar._axles(D)):
            _cladding(ctx, 'clad_%sr' % ('f' if ai == 0 else 'r'), s_ax)
        _sill(ctx)
        for nm in ('clad_fl', 'clad_rl', 'clad_sill_l'):
            ctx.part(nm, bevel=0)                 # named, so the right-hand piece is written as a pair
        return True
    if t == 'roof_rails':
        # silver rails (the car's bright line under sodium), black crossbars
        rails = ctx.part('roof_rails', bevel=0)
        pm = fcar.CarModel(D)
        fcar.add_part(pm, dict(p, bars=[]))
        for tri in pm.mesh.tris:
            rails.add(np.array(tri), 'chrome')
        s0, s1, x, h = p['s0'], p['s1'], p['x'], p.get('h', 0.06)
        y0 = max(pl(D['top'], s0), pl(D['top'], s1)) - 0.03 + h * 0.7
        over = p.get('bar_over', 0.05)
        bars = ctx.part('rack_bars', bevel=0)
        for s in p.get('bars', []):
            P.obox(bars, (0.0, y0 + 0.03, z(s)), (2 * x + 2 * over, p.get('bar_h', 0.028), 0.045), np.eye(3), 'plastic')
            for sx in (1, -1):                    # the end caps
                P.obox(bars, (sx * (x + over + 0.006), y0 + 0.03, z(s)), (0.012, p.get('bar_h', 0.028) + 0.006, 0.05),
                       np.eye(3), 'rubber')
        return True
    if t == 'roof_spoiler':
        # the spoiler sits on the tailgate's top edge and goes up with it
        pm = fcar.CarModel(D)
        fcar.add_part(pm, dict(p, brake_light=False, s0=D['cabin']['C'] + SPOILER_IN))
        sp = ctx.part('spoiler', parent='hinge_hatch', bevel=0.006)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            sp.add(np.array(tri), P.MATMAP.get(mm, mm), P.SKIN)
        # the high brake lamp: a strip in its trailing edge
        th = p.get('thick', 0.03)
        zc = z(p['s1']) + 0.003
        y = p['y1'] + th * 0.5
        hb = ctx.part('brake_c', parent='hinge_hatch', bevel=0)
        hb.add(P.facing([np.array([(-0.30, y - 0.012, zc), (0.30, y - 0.012, zc), (0.30, y + 0.012, zc), (-0.30, y + 0.012, zc)])],
                        (0, 0, 1))[0], 'glow_brake')
        return True
    return False


# --------------------------------------------------------------------------
# Cladding
# --------------------------------------------------------------------------
def _skin(ctx, s, y, off=0.0):
    """The right flank at (s, y), `off` proud of it."""
    q = P.laid_on(ctx.body_tris, 'right', [(ctx.z(s), y)], off)
    return None if q is None else np.asarray(q[0], float)


def _cladding(ctx, name, s_ax):
    """One arch piece (right side; the left is its mirror image): a band
    CLAD_BAND wide round the arch with its outer face at CLAD_X, a rolled lip
    from the face into the wheel well, a top wall back to the flank, end
    walls down at the sill, rivets along the arch edge. It lies on the skin
    (no cut), so the arch liner and the body's own arch edge stay as they are."""
    D, z = ctx.D, ctx.z
    Ra, yc = _arch(D)
    part = ctx.part(name, bevel=0)
    r_in, r_out = Ra + 0.004, Ra + CLAD_BAND
    y_foot = pl(D['floor'], s_ax) + 0.04
    a0 = math.asin(max(-0.95, (y_foot - yc) / r_in))
    n = 14
    angs = [a0 + (math.pi - 2 * a0) * k / n for k in range(n + 1)]
    x_lip = pl(D['hw'], s_ax) - D.get('sill_in', 0.03) - P.LIP
    rows = []
    for a in angs:
        si, yi = s_ax - r_in * math.cos(a), yc + r_in * math.sin(a)
        so, yo = s_ax - r_out * math.cos(a), yc + r_out * math.sin(a)
        sk = _skin(ctx, so, yo, -0.003)
        if sk is None:
            continue
        rows.append((np.array([x_lip, yi, z(si)]), np.array([CLAD_X, yi, z(si)]), np.array([CLAD_X, yo, z(so)]), sk, a))
    side = np.array([1.0, 0.0, 0.0])
    for A, B in zip(rows, rows[1:]):
        a_mid = 0.5 * (A[4] + B[4])
        radial = np.array([0.0, math.sin(a_mid), -math.cos(a_mid)])
        part.add(P.facing([[A[0], B[0], B[1], A[1]]], -radial)[0], 'plastic')            # the lip into the well
        part.add(P.facing([[A[1], B[1], B[2], A[2]]], side)[0], 'plastic', P.SKIN)       # the outer face
        part.add(P.facing([[A[2], B[2], B[3], A[3]]], radial + side * 0.3)[0], 'plastic', P.SKIN)   # the top wall
    for R_ in (rows[0], rows[-1]):                                                        # the two feet
        part.add(P.facing([[R_[0], R_[1], R_[2], R_[3]]], (0, -1, 0))[0], 'plastic')
    # rivet heads along the arch edge
    r_mid = r_in + 0.028
    for k in range(CLAD_RIVETS):
        a = a0 + 0.18 + (math.pi - 2 * a0 - 0.36) * k / (CLAD_RIVETS - 1)
        c = np.array([CLAD_X, yc + r_mid * math.sin(a), z(s_ax - r_mid * math.cos(a))])
        K.cyl(part, c, c + side * 0.004, 0.009, 4, 'steel', caps=(False, False), r_b=0.0)


def _sill(ctx):
    """The sill panel joining the two arch pieces under the doors (right side)."""
    D, z = ctx.D, ctx.z
    Ra, _ = _arch(D)
    axles = fcar._axles(D)
    s0, s1 = axles[0] + Ra + CLAD_BAND - 0.004, axles[1] - Ra - CLAD_BAND + 0.004
    y0, y1, x = SILL
    part = ctx.part('clad_sill_r', bevel=0)
    st = [s0 + (s1 - s0) * k / 6 for k in range(7)]
    top = [_skin(ctx, s, y1, -0.003) for s in st]
    bot = [_skin(ctx, s, y0, -0.003) for s in st]
    face = lambda s, y: np.array([x, y, z(s)])
    for i in range(len(st) - 1):
        a, b = st[i], st[i + 1]
        part.add(P.facing([[face(a, y0), face(b, y0), face(b, y1), face(a, y1)]], (1, 0, 0))[0], 'plastic', P.SKIN)
        part.add(P.facing([[face(a, y1), face(b, y1), top[i + 1], top[i]]], (0.3, 1, 0))[0], 'plastic', P.SKIN)
        part.add(P.facing([[face(a, y0), face(b, y0), bot[i + 1], bot[i]]], (0.3, -1, 0))[0], 'plastic')
    for s, tp, bt, out in ((st[0], top[0], bot[0], -1), (st[-1], top[-1], bot[-1], 1)):
        part.add(P.facing([[face(s, y0), face(s, y1), tp, bt]], (0, 0, out))[0], 'plastic')
    for k in range(6):
        s = s0 + 0.10 + (s1 - s0 - 0.20) * k / 5
        c = face(s, 0.5 * (y0 + y1))
        K.cyl(part, c, c + np.array([0.004, 0, 0]), 0.009, 4, 'steel', caps=(False, False), r_b=0.0)


# --------------------------------------------------------------------------
# Fittings
# --------------------------------------------------------------------------
def _door_hinge(D, R, s, nm, panel, belt_s):
    sx = 1 if nm == 'r' else -1
    x = pl(D['hw'], s) + HINGE_OUT
    return {'pos': [round(sx * x, 4), round(0.5 * (R['door_y0'] + pl(D['belt'], belt_s)), 4), round(fcar._s2z(D, s), 4)],
            'axis': [0, 1, 0], 'open_sign': sx, 'open_deg': 60, 'panel': panel}


def _trim_door_glass(ctx):
    """The front door glass ends A_TUCK in from the windscreen's side edge,
    under the A-pillar strip: the loft's side glass and windscreen do not
    share that edge exactly, so glass and seal running right up to it cross
    the windscreen and the pillar when shut. The edge is the windscreen's own
    outermost vertex at each station; each glass polygon is cut on the
    stretch its centre lies beside."""
    ws = ctx.parts.get('glass_windshield')
    if ws is None:
        return
    corner = {}
    for q in ws.polys:
        for v in np.asarray(q, float):
            k = round(float(v[2]), 3)
            if k not in corner or v[0] > corner[k][0]:
                corner[k] = v
    line = [corner[k] for k in sorted(corner)]
    across = np.array([0.30, -1.0, 0.0])        # down the side glass from the pillar, right side
    cuts = []
    for a, b in zip(line, line[1:]):
        d = b - a
        if np.linalg.norm(d) < 0.02:
            continue
        d /= np.linalg.norm(d)
        n = across - (across @ d) * d
        n /= np.linalg.norm(n)
        cuts.append((a[2], b[2], n, float(n @ a) + A_TUCK))
    for name in ('glass_door_r', 'seal_door_r'):
        pt = ctx.parts.get(name)
        if pt is None:
            continue
        keep = list(zip(pt.polys, pt.mats, pt.kind, pt.shut))
        pt.polys, pt.mats, pt.kind, pt.shut = [], [], [], []
        for q, m, k, sh in keep:
            q = np.asarray(q, float)
            zc = float(q[:, 2].mean())
            cut = next((c for c in cuts if c[0] - 1e-6 <= zc <= c[1] + 1e-6), None)
            ins = q if cut is None else P.clip_poly(q, cut[2], cut[3])[0]
            if ins is None:
                continue
            if ins is q or (len(ins) == len(q) and np.allclose(ins, q)):
                pt.add(q, m, k, sh)
            else:
                pt.add(ins, m, k)


def _wipers(ctx):
    """The common wipers, with their arm pivots on the scuttle behind the
    hood's shut line instead of on the hood: the hood lifts forward from a
    hinge at its rear edge, and its rear edge would come up through them."""
    D, z, on_top = ctx.D, ctx.z, ctx.on_top
    sA = D['cabin']['A']
    s_w = sA + 0.075
    g0, g1 = on_top(0.3, sA + 0.05), on_top(0.3, sA + 0.30)
    up_glass = (g1 - g0) / np.linalg.norm(g1 - g0)
    n_glass = np.cross(np.array([1.0, 0, 0]), up_glass)
    if n_glass[1] < 0:
        n_glass = -n_glass
    for nm, x0, x1 in (('r', 0.06, 0.52), ('l', -0.50, -0.04)):
        wp = ctx.part('wiper_' + nm, bevel=0)
        wp.polys, wp.mats, wp.kind, wp.shut = [], [], [], []
        a_, b_ = on_top(x0, s_w) + n_glass * 0.012, on_top(x1, s_w) + n_glass * 0.012
        P.obox(wp, (a_ + b_) / 2, (np.linalg.norm(b_ - a_), 0.012, 0.016), P.frame_basis(b_ - a_, n_glass), 'rubber')
        pivot = on_top(x0 + 0.02, sA + WIPER_PIVOT) + n_glass * 0.010
        mid = (a_ + b_) / 2 + n_glass * 0.010
        P.obox(wp, (pivot + mid) / 2, (np.linalg.norm(mid - pivot), 0.008, 0.012), P.frame_basis(mid - pivot, n_glass), 'plastic')


def _fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R
    hinges = ctx.info.setdefault('hinges', {})

    # ---- doors: the front pair's hinge moved just outboard of the skin, the rear pair's own
    for nm in ('r', 'l'):
        hinges['hinge_door_' + nm] = _door_hinge(D, R, R['door_s0'], nm, 'door_' + nm, R['door_s0'])
        hinges['hinge_door_r' + nm] = _door_hinge(D, R, RDOOR[0], nm, 'door_r' + nm, RDOOR[0])
    # the hood: hinged just behind and above its rear edge, so the whole panel
    # lifts forward and up (a hinge ahead of the edge dips the rear corners into the fenders)
    cab_a = D['cabin']['A']
    hinges['hinge_hood'] = {'pos': [0.0, round(pl(D['top'], cab_a) + 0.002, 4), round(z(cab_a) + 0.005, 4)],
                            'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': 45, 'panel': 'hood'}
    _trim_door_glass(ctx)
    _wipers(ctx)
    # the rear door's handle, at the front door's height
    hs = RDOOR[1] - 0.16
    hy = pl(D['belt'], R['door_s1'] - 0.16) - 0.075
    part('handle_door_rl', parent='hinge_door_rl', bevel=0)     # named: the right one is written as a pair
    hp = part('handle_door_rr', parent='hinge_door_rr', bevel=0)
    P.decal(hp, D, ctx.body_tris, {'view': 'right', 'rect': (hs - 0.065, hy - 0.022, hs + 0.065, hy + 0.022), 'cell': 0.2},
            'rubber', 0.002)
    c = P.laid_on(ctx.body_tris, 'right', [(z(hs), hy)], 0.009)
    if c is not None:
        P.obox(hp, c[0], (0.014, 0.016, 0.105), np.eye(3), 'chrome')
    # behind the shut line between the two doors: a dark pillar face, so the gap is never a hole
    by0, by1 = R['door_y0'], pl(D['belt'], RDOOR[0])
    xb = pl(D['hw'], RDOOR[0]) - 0.11             # inboard of both doors' turned-in edges (they reach 0.10 in at the belt)
    part('pillar_b_shut_l', bevel=0)
    part('pillar_b_shut_r', bevel=0).add(
        P.facing([np.array([(xb, by0, z(RDOOR[0] - 0.03)), (xb, by0, z(RDOOR[0] + 0.03)),
                            (xb, by1, z(RDOOR[0] + 0.03)), (xb, by1, z(RDOOR[0] - 0.03))])], (1, 0, 0))[0], 'under_paint')

    # ---- the nose: stacked twin lamps, a driving lamp over an amber blinker
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        xa, xb_ = sorted((sx * HEAD[0], sx * HEAD[2]))
        K.lay(ctx, head, 'front', K.rect2(xa - 0.010, TURN_F[1] - 0.010, xb_ + 0.010, HEAD[3] + 0.010), 'plastic', 0.003)
        K.lay(ctx, head, 'front', K.rect2(xa, HEAD[1], xb_, HEAD[3]), 'glow_lens', 0.006)
        q = K.lay(ctx, head, 'front', K.ellipse(0.5 * (xa + xb_), 0.5 * (HEAD[1] + HEAD[3]), 0.040, 0.034, 10), 'glow_head', 0.008)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = K.lamp_centre(q)
        K.lay(ctx, part('turn_f' + nm, bevel=0), 'front', K.rect2(xa, TURN_F[1], xb_, TURN_F[3]), 'glow_turn', 0.006)

    # ---- the tail: split lamps
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xs = lambda a, b: sorted((sx * a, sx * b))
        blk = part('lamp_block_' + nm, bevel=0)
        xa, xb_ = xs(UPPER[0], UPPER[2])
        K.lay(ctx, blk, 'rear', K.rect2(xa - 0.008, UPPER[1] - 0.008, xb_ + 0.008, UPPER[3] + 0.006), 'plastic', 0.003)
        xa, xb_ = xs(WRAP[0], WRAP[2])
        K.lay(ctx, blk, 'rear', K.rect2(xa - 0.008, WRAP[1] - 0.004, xb_ + 0.008, WRAP[3] + 0.008), 'plastic', 0.003)
        xa, xb_ = xs(LOWER[0], LOWER[2])
        K.lay(ctx, blk, 'rear', K.rect2(xa - 0.008, LOWER[1] - 0.008, xb_ + 0.008, LOWER[3] + 0.008), 'plastic', 0.003)
        # upper: the amber blinker inboard, the running lamp outboard with the brake core in it, its wrap
        tail = part('tail_' + nm, bevel=0)
        xa, xb_ = xs(UPPER_TURN + 0.005, UPPER[2])
        q = K.lay(ctx, tail, 'rear', K.rect2(xa, UPPER[1], xb_, UPPER[3]), 'glow_tail', 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = K.lamp_centre(q)
        xa, xb_ = xs(WRAP[0], WRAP[2])
        K.lay(ctx, tail, 'rear', K.rect2(xa, WRAP[1], xb_, WRAP[3]), 'glow_tail', 0.006)
        xa, xb_ = xs(UPPER[0], UPPER_TURN)
        K.lay(ctx, part('turn_r' + nm, bevel=0), 'rear', K.rect2(xa, UPPER[1], xb_, UPPER[3]), 'glow_turn', 0.006)
        xa, xb_ = xs(BRAKE[0], BRAKE[2])
        K.lay(ctx, part('brake_' + nm, bevel=0), 'rear', K.rect2(xa, BRAKE[1], xb_, BRAKE[3]), 'glow_brake', 0.009)
        # lower: the reversing lamp inboard, a red running lamp outboard
        xa, xb_ = xs(LOWER[0], LOWER_REV)
        K.lay(ctx, part('reverse_' + nm, bevel=0), 'rear', K.rect2(xa, LOWER[1], xb_, LOWER[3]), 'glow_reverse', 0.006)
        xa, xb_ = xs(LOWER_REV + 0.005, LOWER[2])
        K.lay(ctx, part('tail_low_' + nm, bevel=0), 'rear', K.rect2(xa, LOWER[1], xb_, LOWER[3]), 'glow_tail', 0.006)

    # ---- the tailgate: it hangs on the roof's rear edge and takes its spoiler, glass, plate, lamp, handle and wiper up
    hs = D['cabin']['C']
    hinges['hinge_hatch'] = {'pos': [0.0, round(pl(D['top'], hs) - 0.005, 4), round(z(hs), 4)],
                             'axis': [1, 0, 0], 'open_sign': -1, 'open_deg': 70, 'panel': 'hatch'}
    py = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    lamp = part('plate_lamp', parent='hinge_hatch', bevel=0)
    K.lay(ctx, lamp, 'rear', K.rect2(-0.11, py + 0.012, 0.11, py + 0.030), 'plastic', 0.012)
    K.lay(ctx, lamp, 'rear', K.rect2(-0.09, py + 0.015, 0.09, py + 0.024), 'glow_lens', 0.0135)
    pull = part('handle_hatch', parent='hinge_hatch', bevel=0)
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, 0.80)], 0.008)
    if c is not None:
        P.obox(pull, c[0], (0.16, 0.022, 0.014), np.eye(3), 'plastic')
    wp = part('wiper_rear', parent='hinge_hatch', bevel=0)
    a = P.laid_on(ctx.body_tris, 'rear', [(-0.02, 1.21)], 0.012)
    b = P.laid_on(ctx.body_tris, 'rear', [(0.42, 1.23)], 0.012)
    if a is not None and b is not None:
        a, b = a[0], b[0]
        P.obox(wp, (a + b) / 2, (np.linalg.norm(b - a), 0.014, 0.012), P.frame_basis(b - a, (0, 1, 0)), 'rubber')
        P.obox(wp, a + np.array([0.0, -0.025, 0.006]), (0.04, 0.04, 0.02), np.eye(3), 'plastic')
    # what shows when it is up: the boot floor and the back of the rear bench
    cargo = part('cargo', bevel=0)
    x, y, s0, s1 = 0.72, 0.62, axles[1] - 0.10, L - 0.06
    cargo.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, y, z(s1)), (-x, y, z(s1))]], (0, 1, 0))[0], 'under_paint')
    cargo.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, 1.10, z(s0) - 0.10), (-x, 1.10, z(s0) - 0.10)]], (0, 0, 1))[0], 'rubber')

    # ---- fuel flap on the left rear quarter, over the rear cladding
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])
    # its hinge out past the flap's most outboard point: the flank leans in,
    # and a hinge on the skin at mid height swings the flap's lower front corner into it
    fh = hinges['hinge_fuel_flap']
    fh['pos'][0] = round(min(float(np.min(q[:, 0])) for q in ctx.parts['fuel_flap'].polys) - 0.006, 4)

    # ---- antenna: a short fin at the back of the roof, between the rails
    base = ctx.on_top(0.0, 3.62)
    if base is not None:
        P.obox(part('antenna', bevel=0), base + np.array([0.0, 0.028, 0.0]), (0.05, 0.056, 0.15), np.eye(3), 'plastic')

    # ---- brakes: the calipers stay on the uprights (the discs are in the wheels' meshes); black stock
    for ai, tagf, dr in ((0, 'f', DISC_F), (1, 'r', DISC_R)):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        track = wh['track'] if ai == 0 else wh.get('track_rear', wh['track'])
        for sx, nm in ((1, 'r'), (-1, 'l')):
            hub_x = sx * (track / 2 - tw / 2 - 0.018)
            P.obox(part('caliper_' + tagf + nm, bevel=0), (hub_x, r_w + dr - 0.035, z(axles[ai])), (0.04, 0.07, 0.12),
                   np.eye(3), 'plastic')

    # ---- what shows in the wheel wells (it is lifted: the low camera sees in)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        sf = part('susp_f' + nm, bevel=0)          # a strut and its lower arm
        K.cyl(sf, (sx * 0.60, r_w + 0.02, z(axles[0])), (sx * 0.58, r_w + 0.36, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        K.cyl(sf, (sx * 0.30, r_w - 0.08, z(axles[0])), (sx * 0.60, r_w - 0.06, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))
        sr = part('susp_r' + nm, bevel=0)          # a multi-link's trailing arm and its shock
        K.cyl(sr, (sx * 0.60, r_w + 0.02, z(axles[1] - 0.42)), (sx * 0.60, r_w - 0.02, z(axles[1])), 0.022, 4, 'steel', caps=(False, False))
        K.cyl(sr, (sx * 0.57, r_w + 0.03, z(axles[1]) + 0.08), (sx * 0.55, r_w + 0.34, z(axles[1]) + 0.06), 0.028, 6, 'steel', caps=(False, False))

    # ---- the skid plate under the nose
    P.obox(part('skid_plate', bevel=0), (0.0, 0.212, z(0.62)), (0.72, 0.010, 0.60), np.eye(3), 'steel')

    # ---- under the hood: the flat four (low and wide), its intake, the radiator, the battery
    en = part('engine', bevel=0)
    P.obox(en, (0.0, 0.56, z(0.78)), (0.66, 0.26, 0.40), np.eye(3), 'steel')
    P.obox(en, (0.0, 0.72, z(0.80)), (0.40, 0.06, 0.26), np.eye(3), 'plastic')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.62, z(0.42)), (0.66, 0.36, 0.04), np.eye(3), 'rubber')
    P.obox(part('bay_battery', bevel=0), (-0.46, 0.66, z(0.55)), (0.22, 0.18, 0.17), np.eye(3), 'plastic')


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
    axles = fcar._axles(D)
    A['bay_engine'] = {'pos': [0.0, 0.56, z(0.78)]}
    A['bay_radiator'] = {'pos': [0.0, 0.62, z(0.42)]}
    # the boost branch of its tree: the turbo beside the right bank, the intercooler on top under the hood scoop
    A['bay_turbo'] = {'pos': [0.42, 0.52, z(0.90)]}
    A['bay_intercooler'] = {'pos': [0.0, 0.84, z(0.86)]}
    A['diff'] = {'pos': [0.0, D['wheel']['r'], z(axles[1])]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'regions': {
        'nose_s': 0.36,                    # the front bumper ends ahead of the front cladding
        'door_s0': DOOR_S0,
        'tail_s': 4.04, 'tail_y': 0.58,    # the rear bumper, behind the rear cladding and under the tailgate
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is one tailgate
    'no_antenna': True,                    # the kit stands its own fin on the roof
    'hinge_of': {'door_rr': 'hinge_door_rr', 'door_rl': 'hinge_door_rl',
                 'glass_door_rr': 'hinge_door_rr', 'glass_door_rl': 'hinge_door_rl',
                 'hatch': 'hinge_hatch', 'glass_backlight': 'hinge_hatch', 'plate_r': 'hinge_hatch'},
    'plates': PLATES,
    'asymmetric': {
        'wiper_rear': 'one rear wiper, on the tailgate glass',
        'fuel_recess': 'one filler, on the left rear quarter',
        'fuel_flap': 'one filler, on the left rear quarter',
        'bay_battery': 'one battery, front left',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'vented disc 316 mm, black caliper', 'rear': 'vented disc 300 mm, black caliper'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 2, 'blinkers_front': 2, 'blinkers_rear': 2,
              'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1, 'wipers': 3, 'fuel_flap': 1, 'doors': 4,
              'condition': 0.5},
    # stance data (car-and-parts audit J2, car-shape-and-stance S3/S4): numbers for the
    # shared stance pass, NOT applied here or in the game; the model stands as the sheet.
    # Rally-raised: no drop and no push-out (the shape note keeps its 22 cm clearance)
    'stance': {'ride_height': 0.22, 'arch_gap': [0.045, 0.045], 'rake_deg': 0.0, 'rear_camber_deg': 0.0,
               'body_drop': 0.0, 'wheel_push_out': 0.0, 'flare_x': CLAD_X,
               'tyre_outer_x': [0.8975, 0.9125], 'note': 'front 235 / rear 265 tyres on a 1.56 m track; not applied'},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
