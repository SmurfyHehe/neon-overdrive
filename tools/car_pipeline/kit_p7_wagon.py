"""P7, the shop wagon (Bramley 240 Estate): what it adds to the common parts recipe.

A late-1980s front-drive estate on 14-inch steelies, T1, sheet
notes/car-sheets/p7_wagon (DECIDED, Roy 228-231: ghost shop lettering, glass
all round, barn doors, the swap keeps the stock look). Rebuilt for looks on
2026-10-14 (Roy 1546: "our work wagon looks like shit"): the first build's
lamps, plates and strips were laid on the loft and hovered off the merged
panels, the rub strip ran through the wheel arches, the nose was a flat slab
with two dots for lamps, the tail two amber bars. This kit lays everything on
the built skin (the tuner kit's helpers, with this car's own skin list SKIN:
its doors and every glass, as the tail is mostly glass), so
tests/fleet/exterior_fit.gd holds it to zero clashes.

What it has that the common recipe does not:
  - two barn doors (`barn_l/r`) cut from the tail between the bumper band and
    the header glass, split on the centre line with a 5 mm gap (Roy,
    2026-10-11), each with its half of the rear glass (`glass_panels`), a
    seal round it, a chrome pull; the rear wiper on the right door; exposed
    hinges (`barn_hinge_*`) with the axis 12 mm outboard of the door's edge
    and 12 mm behind the tail face, so the whole door is ahead of its axis
    and swings back and inward, clear of the lamp column
  - a black plastic bumper band front and rear (`bumper_*_band`): the skin's
    own faces copied out along their normals, 3 cm at the face easing to
    12 mm along the sides to the arch, walled back to the skin; the plate,
    the blinkers / reversing lamps and the plate lamp on its flat face
  - square flush headlamps in chrome bezels (most of the lamp lit), a slot
    grille with two slats between them
  - tall rear lamp columns bumper to the header glass: amber bottom third,
    red running lamp, red brake lamp on top, ribbed; the housing in two
    halves round the tail's ledge; the brake lamp on the roof edge on the
    fixed header glass (85 mm tall, the 100 m rule); outboard of the doors
    the loft's backlight is the columns' pillar, in paint (`glass_to_paint`)
  - the black rub strip the full length ABOVE the arches (0.69-0.73), the
    door's piece on the door, each piece laid between the plan's knots
  - the wear the sheet asks for: the old shop name sanded nearly off both
    flanks (`ghost_l/r`, reads left to right on both sides, so not a mirror
    pair), rust bloom round the rear arches laid cell by cell, a primer
    patch on the right barn door, one hubcap missing
  - the A-pillar strip in two legs: over the windshield on the body, over the
    door's glass on the door (`pillar_a_door_*`): a fixed strip over glass
    that swings out is crossed by it
  - aluminium drip-rail gutter round the roof, a mast on the left front fender
  - small discs in front, 200 mm drums at the rear; the strut and arms in
    the wells; the transverse engine, radiator and battery under the hood;
    nothing hangs under the floor (the spare crossed it)

Visual rebuild only: the loft's dimensions (4.30 x 1.74 x 1.55, wheelbase
2.60), the collision box, the physics and the tune are not touched. The nose
of the loft is 8 cm taller (cars.py P7 `top`, a stand-in anyway), so the
lamps and grille sit on a face instead of on the hood's roll.
"""
import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl
import kit_p3_tuner as T

WAGON_NO_CAP = 'rl'    # the sheet: one hubcap missing, left rear, bare black steel
BARN_HW = 0.59         # each barn door reaches this far from the centre line (its edge swings clear of the lamp column)
BARN_Y0 = 0.56         # and down to the top of the bumper
BARN_Y1 = 1.44         # and up to here: the glass above is a fixed header strip, the roof brake lamp on it
BARN_S0 = 4.10         # nothing ahead of this is a door (the cut's planes bound it; the tail face starts at 4.22)
BARN_GAP = 0.005       # between the two doors (Roy, 2026-10-11: 5 mm; the sheet's 6 is over the parts rule's 5)
HINGE_OUT = 0.012      # the barn hinge axis this far outboard of the door's edge and behind the tail face: an exposed
HINGE_AFT = 0.012      # hinge, as on a van, so every point of the door is ahead of the axis and swings back and inward
WELL_X = 0.46          # the wheel wells' inner wall (the tuner's): a front tyre at full lock clears it
PILLAR_LIFT = 0.004 + T.PILLAR_LIFT   # the A-pillar strip's lift over the glass (the common 4 mm plus the tuner's)

# ---- nose (front view x, y)
BUMPER_F = (0.36, 0.54)             # the black bumper band, bottom and top
BUMPER_IN = 0.68                    # the flat slab across the face reaches this far; the corner pieces take over
BUMPER_PROUD = 0.03                 # how far the band stands off the body
HEAD = (0.50, 0.68, 0.57, 0.71)     # square flush headlamp: x0, x1, y0, y1 (the sheet: 0.18 x 0.16, here 0.18 x 0.14 on the face)
GRILLE = (0.47, 0.61, 0.67)         # the slot between the lamps: half width, y0, y1
TURN_F = (0.54, 0.68, 0.41, 0.49)   # amber blinkers on the bumper, beside the plate
PLATES = {'plate_f': ('front', 0.445, 0.26, 0.055), 'plate_r': ('rear', 0.445, 0.26, 0.055)}   # 520 x 110, on the bumper bands

# ---- tail (rear view x, y)
BUMPER_R = (0.36, 0.53)             # its top under the bumper panel's shut line (0.54): a ray in the gap goes through the car
LAMP_X = (0.62, 0.725)              # the tall lamp columns outboard of the doors (the roof corner is at 0.74: no wider)
COL_Y = (0.57, 1.45)                # bumper top to under the header glass
LEDGE = (0.866, 0.886)              # the tail's ledge (belt 0.872 to the slope's foot 0.878) is between the housing's two halves
AMBER = (0.57, 0.835)               # the bottom third: blinker
TAIL_RED = (0.85, 1.14)             # the running lamp (its centre 300 mm under the brake lamp's: the 100 m rule)
BRAKE = (1.155, 1.44)               # the brake lamp on top
RIB = 0.15                          # a dark rib across the lenses every 15 cm
REVERSE = (0.50, 0.64, 0.41, 0.49)  # reversing lamps on the bumper
BRAKE_C = (-0.16, 1.45, 0.16, 1.535)    # the roof-edge brake lamp on the header glass (85 mm tall: tests/fleet/exterior_fit.gd TAIL_TALL 80)

# ---- flanks (s from the nose, y)
RUB_Y = (0.69, 0.73)                # the rub strip: just over the arch lips (0.678), the sheet's 40 mm
RUB_S = (0.26, 4.20)
RUB_KNOTS = (1.25, 2.80, 2.95, 3.75)   # the plan's knots (cars.py P7 hw): a strip piece never spans one, so its walls follow the skin
GHOST_Y = (0.745, 0.845)            # the ghost lettering between the strip and the belt (0.86)
GHOST_DOOR = ('WALT\'S', 1.20)      # on the front door, from this s
GHOST_QUARTER = ('GARAGE', 2.22)    # on the rear quarter
GHOST_CELL = 0.0143                 # one cell of the 5 x 7 letters: 7 cells = 10 cm tall
GHOST_PITCH = 0.09
GHOST_SANDED = 0.40                 # this share of the cells is sanded away
FLAP = (3.92, 0.795)                # fuel flap on the right rear quarter, over the strip
DISC_R = 0.118                      # small solid front discs (the sheet)
CALIPER_IN = 0.0185
RAIL_LIFT = 0.012                   # the gutter rail's centre over the roof corner (was 8 mm: it cut 2 mm into the roof)
RUST_CELL = 0.035                   # the rust bloom is laid in cells this big (each follows the skin's folds)
RUST_IN = 0.014                     # from the arch lip's shelf outward (the shelf itself is bevelled)
# the built skin a lamp, strip or foot is laid on: the common panels, the wagon's own doors and every glass
# (the tail is mostly glass: a rear-view ray through it would land on the hood)
SKIN = T.SKIN_PARTS + ('barn_l', 'barn_r', 'glass_barn_l', 'glass_barn_r', 'glass_backlight', 'glass_windshield',
                       'glass_door_l', 'glass_door_r', 'glass_quarter_l', 'glass_quarter_r', 'sail_l', 'sail_r',
                       'pillar_b_l', 'pillar_b_r')

# 5 x 7 block letters, row 0 at the top
GLYPHS = {
    'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
    'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    "'": ['..#..', '..#..', '.....', '.....', '.....', '.....', '.....'],
    'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    'G': ['.####', '#....', '#....', '#.###', '#...#', '#...#', '.###.'],
    'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
}


# --------------------------------------------------------------------------
# Panels
# --------------------------------------------------------------------------
def _cuts(D, R, z, cut):
    """The two barn doors: the tail from the bumper band up to the header
    glass, each with its half of the rear glass, split on the centre line."""
    everything = lambda ps: np.ones(len(ps), bool)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        # every cut trims GAP / 2 a side; the centre line gets the rest of BARN_GAP
        cut('barn_' + nm, [((sx, 0, 0), (BARN_GAP - P.GAP) / 2), ((-sx, 0, 0), -BARN_HW), ((0, 1, 0), BARN_Y0),
                           ((0, -1, 0), -BARN_Y1), ((0, 0, 1), z(BARN_S0))], everything, True)
    return ['barn_r', 'barn_l']


# --------------------------------------------------------------------------
# Sheet decals and parts
# --------------------------------------------------------------------------
def _decal(ctx, d):
    """Every sheet decal is built here as a part of its own (fittings)."""
    return d['mat'] in ('head', 'turn', 'tail', 'grille') or d.get('tag') in ('fbumper', 'rbumper', 'rub')


def _sheet_part(ctx, p):
    if p['type'] != 'mirrors':
        return False
    _skin_on(ctx)
    with T._on_skin(ctx):
        _mirrors(ctx, p)
    return True


def _mirrors(ctx, p):
    """The sheet's mirrors (the tuner's recipe) on a foot down to the door
    top; the foot's outer edge 24 mm out from the glass (the tuner's 34 hangs
    over this door's narrower ledge, 15 mm into the door)."""
    pm = fcar.CarModel(ctx.D)
    fcar.add_part(pm, p)
    for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
        tri = np.array(tri)
        nm = 'l' if tri[:, 0].mean() < 0 else 'r'
        ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
    s_ = p.get('s', ctx.D['cabin']['A'] + 0.14)
    x7, y7 = fcar._section_at(ctx.D, s_)[7][:2]
    y_stub = y7 + p.get('up', 0.09) - 0.025
    xa, xb = x7 + 0.004, x7 + 0.024
    z0, z1 = ctx.z(s_) - 0.008, ctx.z(s_) + 0.045
    for sx, nm in ((1, 'r'), (-1, 'l')):
        feet = [P.laid_on(ctx.body_tris, 'top', [(sx * x, z_)], -0.0005) for x in (xa, xb) for z_ in (z0, z1)]
        if any(f is None for f in feet):
            continue
        part = ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0)
        lo = [np.asarray(f[0], float) for f in feet]
        hi = [np.array([q[0], y_stub, q[2]]) for q in lo]
        c = np.mean(lo + hi, axis=0)
        for a, b in ((0, 1), (1, 3), (3, 2), (2, 0)):
            q = [lo[a], lo[b], hi[b], hi[a]]
            part.add(P.facing([q], np.mean(q, axis=0) - c)[0], 'plastic')
        part.add(P.facing([[hi[0], hi[1], hi[3], hi[2]]], (0, 1, 0))[0], 'plastic')


def _skin_on(ctx):
    """ctx.skin_tris from this car's SKIN list (T._on_skin would build it from
    the common list, without the doors and the glass)."""
    if hasattr(ctx, 'skin_tris'):
        return
    tris = []
    for name in SKIN:
        part = ctx.parts.get(name)
        if part is None:
            continue
        tris += [t for poly, kind in zip(part.polys, part.kind) if kind == P.SKIN for t in T._fans(poly)]
    ctx.skin_tris = np.array(tris, float).reshape(-1, 3, 3)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def _sd(ctx, part, view, rect, mat, off):
    """A rect laid on the built skin as the skin itself (the tuner's), from this car's SKIN list."""
    T._skin_decal(ctx, part, view, rect, mat, off, skin=SKIN)


def _rim(ctx, part, view, pts, off, mat='plastic', step=0.03):
    """The tuner's rim (walls from an outline laid `off` proud down to the
    skin), its outline first split every `step`: a wall whose foot is one
    chord across a twisted panel lets the panel through it."""
    fine = []
    n = len(pts)
    for i in range(n):
        a, b = np.asarray(pts[i], float), np.asarray(pts[(i + 1) % n], float)
        k = max(1, int(np.ceil(np.linalg.norm(b - a) / step)))
        fine += [tuple(a + (b - a) * j / k) for j in range(k)]
    T._rim(ctx, part, view, fine, off, mat)


def _plate(ctx, part, view, rect, mat, off, step=0.03):
    """A housing or bezel on the skin: the rect laid on it `off` proud, with walls down to it."""
    _sd(ctx, part, view, rect, mat, off)
    _rim(ctx, part, view, K.rect2(*rect), off, mat, step)


def _frame(ctx, part, view, rect, w, mat, off):
    """A frame `w` wide just inside the rect."""
    x0, y0, x1, y1 = rect
    for r in ((x0, y1 - w, x1, y1), (x0, y0, x1, y0 + w), (x0, y0 + w, x0 + w, y1 - w), (x1 - w, y0 + w, x1, y1 - w)):
        _sd(ctx, part, view, r, mat, off)


def _bumper(ctx, name, view, y0, y1, proud):
    """The black plastic bumper: the skin between y0 and y1 from the face back
    to the arch, copied out along its own normals, `proud` at the face easing
    to 12 mm along the sides, walled back to the skin on every edge. It wraps
    the plan's corners because it is the skin's own shape (a slab across the
    face would stand off the corners; the Camel's blade is in chrome)."""
    D, z = ctx.D, ctx.z
    L = D['L']
    front = view == 'front'
    s0, s1 = (0.0, 0.28) if front else (L - 0.28, L)
    ease = lambda s_: s_ if front else L - s_                              # distance back from the face
    p_of = lambda s_: proud if ease(s_) <= 0.06 else (0.012 if ease(s_) >= 0.20 else proud + (0.012 - proud) * (ease(s_) - 0.06) / 0.14)
    ref = np.array([0.0, 0.5 * (y0 + y1), z(s0 + 0.6) if front else z(s1 - 0.6)])   # inside the car: faces point away from it
    faces = []
    # the faces themselves lie on z(s0) / z(s1): the planes sit 2 mm outside them
    planes = [((0, 1, 0), y0), ((0, -1, 0), -y1), ((0, 0, 1), z(s0) - 0.002), ((0, 0, -1), -z(s1) - 0.002)]
    for pname in ('bumper_f', 'fender_fl', 'fender_fr') if front else ('bumper_r',):
        src = ctx.parts.get(pname)
        if src is None:
            continue
        for poly, kind in zip(src.polys, src.kind):
            if kind != P.SKIN:
                continue
            q = np.asarray(poly, float)
            if q[:, 1].max() < y0 or q[:, 1].min() > y1 or q[:, 2].max() < z(s0) or q[:, 2].min() > z(s1):
                continue
            for n, d in planes:
                q, _ = P.clip_poly(q, np.asarray(n, float), d)
                if q is None or len(q) < 3:
                    break
            else:
                q = np.asarray(q, float)
                nf = P.poly_normal(q)
                if np.linalg.norm(nf) < 1e-12:
                    continue
                if nf @ (q.mean(axis=0) - ref) < 0:
                    q = q[::-1]
                faces.append(q)
    if not faces:
        return None
    # weld across the panels' shut gaps too (6 mm > GAP): the band is one piece over them
    flat = np.concatenate(faces)
    key = np.round(flat / 0.006).astype(np.int64)
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    verts = np.zeros((len(uniq), 3))
    np.add.at(verts, inv, flat)
    verts /= np.bincount(inv, minlength=len(uniq))[:, None]
    loops, at = [], 0
    for q in faces:
        loops.append([int(v) for v in inv[at:at + len(q)]])
        at += len(q)
    fn = []
    vn = np.zeros_like(verts)
    for loop, q in zip(loops, faces):
        n = P.poly_normal(q)
        fn.append(n / np.linalg.norm(n))
        for vi in set(loop):
            vn[vi] += n                       # area weighted
    ln = np.linalg.norm(vn, axis=1)
    vn = vn / np.maximum(ln, 1e-12)[:, None]
    # each vertex out along its normal, far enough that every face round it keeps its distance
    cosmin = np.ones(len(verts))
    for loop, n in zip(loops, fn):
        for vi in set(loop):
            cosmin[vi] = min(cosmin[vi], vn[vi] @ n)
    s_of = lambda v: v[2] + D['OHf'] + D['WB'] / 2.0
    out = np.array([v + vn[i] * (p_of(s_of(v)) / max(cosmin[i], 0.6)) for i, v in enumerate(verts)])
    # the face itself stays one flat plane `proud` out (the plates and lamps sit on it): its corners would
    # otherwise lean out with the averaged normals, and a flat lamp over a bulge floats or sinks
    axis = np.array([0.0, 0.0, -1.0 if front else 1.0])
    for loop, n in zip(loops, fn):
        if n @ axis > 0.98:
            for vi in set(loop):
                out[vi] = verts[vi] + n * proud
    b = ctx.part(name, bevel=0)
    for loop in loops:
        b.add(out[loop], 'plastic')
    # what sits on the band (plates, blinkers, reversing lamps) is laid on these, not on the skin: the band's
    # face bulges a little where its vertex normals lean into the corners
    ctx.band_tris = getattr(ctx, 'band_tris', {})
    ctx.band_tris[view] = T._tris([out[loop] for loop in loops])
    centre = out.mean(axis=0)
    for a, c, _ in P.boundary_edges(loops):
        lo_a, lo_c = verts[a] + vn[a] * 0.0005, verts[c] + vn[c] * 0.0005
        q = np.array([lo_a, lo_c, out[c], out[a]])
        b.add(P.facing([q], q.mean(axis=0) - centre)[0], 'plastic')
    # the dark valance under the band
    hw = pl(D['hw'], s0 if front else s1)
    _sd(ctx, b, view, (-hw + 0.10, 0.30 if front else 0.31, hw - 0.10, y0 - 0.004), 'plastic', 0.002)
    return b


def _on_band(ctx, part, view, rect, mat, extra):
    """A lamp or plate on the bumper band: the rect laid on the band's own
    faces, `extra` proud of them."""
    q = P.laid_on(ctx.band_tris[view], view, K.rect2(*rect), extra)
    if q is None:
        return None
    from geom import AXES
    part.add(P.facing([q], -AXES[view])[0], mat)
    return np.array(q)


def _plates(ctx):
    """The common recipe laid the plates 14-17 mm off the loft: that is inside
    the bumper band. Each is laid again on its band: the dark recess, the plate."""
    for name, (view, y, hw_p, hh_p) in PLATES.items():
        pp = ctx.part(name)
        pp.polys, pp.mats, pp.kind, pp.shut = [], [], [], []
        _on_band(ctx, pp, view, (-hw_p - 0.01, y - hh_p - 0.01, hw_p + 0.01, y + hh_p + 0.01), 'rubber', 0.0015)
        _on_band(ctx, pp, view, (-hw_p, y - hh_p, hw_p, y + hh_p), 'plate', 0.003)


def _ghost(ctx, text, s0, sx, part):
    """The old shop name on one flank, sanded nearly off: 5 x 7 block letters
    laid on the skin as `paint_bondo` (the wagon's: a shade off the paint),
    GHOST_SANDED of their cells gone. Reads left to right from outside, so on
    the right flank (nose to the viewer's right) it runs tail-ward."""
    view = 'right' if sx > 0 else 'left'
    z = ctx.z
    y_top = GHOST_Y[1]
    k = 0
    for ci, ch in enumerate(text):
        rows = GLYPHS[ch]
        for r, row in enumerate(rows):
            y1 = y_top - r * GHOST_CELL
            y0 = y1 - GHOST_CELL
            c = 0
            while c < 5:
                if row[c] != '#' or _sanded(ci, r, c, sx):
                    c += 1
                    continue
                c1 = c
                while c1 + 1 < 5 and row[c1 + 1] == '#' and not _sanded(ci, r, c1 + 1, sx):
                    c1 += 1
                sa = s0 + ci * GHOST_PITCH + c * GHOST_CELL
                sb = s0 + ci * GHOST_PITCH + (c1 + 1) * GHOST_CELL
                if sx > 0:                        # the right flank: the text runs the other way along s
                    span = len(text) * GHOST_PITCH - (GHOST_PITCH - 5 * GHOST_CELL)
                    sa, sb = s0 + span - (sb - s0), s0 + span - (sa - s0)
                _sd(ctx, part, view, (z(sa), y0, z(sb), y1), 'paint_bondo', 0.0008)
                k += 1
                c = c1 + 1
    return k


def _sanded(ci, r, c, sx):
    """Which cells the years took: a fixed pattern, the same on both flanks."""
    h = (ci * 73 + r * 31 + c * 17 + 11) % 100
    return h < GHOST_SANDED * 100


def _rust(ctx, sx):
    """Rust bloom round a rear arch: a blotchy half ring of `paint_rust` on the
    quarter over the top half of the arch, from the lip's shelf out 3 to 7 cm,
    laid cell by cell so each follows the skin's folds."""
    D, z = ctx.D, ctx.z
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    yc = wh['r'] + wh.get('arch_lift', 0.0)
    zc = z(fcar._axles(D)[1])
    view = 'right' if sx > 0 else 'left'
    part = ctx.part('rust_r' if sx > 0 else 'rust_l', bevel=0)
    c = RUST_CELL
    k = 0
    for i in range(-16, 17):
        for j in range(0, 16):
            za, ya = zc + i * c, yc + j * c
            zm, ym = za + c / 2, ya + c / 2
            r = np.hypot(zm - zc, ym - yc)
            a = np.arctan2(ym - yc, -(zm - zc))                    # 0 behind the hub, pi ahead of it
            bloom = 0.03 + 0.04 * (0.5 + 0.5 * np.sin(a * 3.7 + 0.8)) * (0.6 + 0.4 * np.cos(a * 7.3))
            if r < Ra + RUST_IN or r > Ra + bloom or ya + c > RUB_Y[0] - 0.004 or ym < yc + 0.05:
                continue
            if (i * 7 + j * 13 + (0 if sx > 0 else 5)) % 9 == 0:    # a few cells of paint left in the bloom
                continue
            _sd(ctx, part, view, (za, ya, za + c, ya + c), 'paint_rust', 0.0008)
            k += 1
    return k


def _pillar_legs(ctx):
    """The A-pillar strips (parts.add_glass_trim: a strip of paint over the
    edge where the windshield meets the side glass) built again in two legs:
    the leg over the windshield stays on the body, the leg over the door's
    glass behind the shut line rides on the door (`pillar_a_door_*`, the
    door frame's front post). A fixed strip 10 mm over glass that swings out
    on a hinge 6 to 50 cm ahead of it is crossed by the glass at 10 degrees."""
    D, R, z = ctx.D, ctx.R, ctx.z
    cab = D['cabin']
    sts = [s_ for s_ in fcar.stations(D) if cab['A'] - 1e-6 <= s_ <= cab['W'] + 1e-6]
    zd = z(R['door_s0'])
    for sx, nm in ((1, 'r'), (-1, 'l')):
        fixed = ctx.part('pillar_a_' + nm, bevel=0)
        for attr in ('polys', 'mats', 'kind', 'shut'):
            setattr(fixed, attr, [])
        door = ctx.part('pillar_a_door_' + nm, parent='hinge_door_' + nm, bevel=0)
        rows = []
        for s_ in sts:
            Pt, _ = fcar.half_section(D, s_)
            p7, p8, p9 = (np.array([sx * Pt[k][0], Pt[k][1], z(s_)]) for k in (7, 8, 9))
            d7, d9 = p7 - p8, p9 - p8
            l7, l9 = np.linalg.norm(d7), np.linalg.norm(d9)
            a = p8 + (d7 / l7 * min(0.040, 0.7 * l7) if l7 > 1e-6 else 0.0)
            c = p8 + (d9 / l9 * min(0.034, 0.5 * l9) if l9 > 1e-6 else 0.0)
            rows.append((a, p8, c))
        want = np.array([sx, 0.6, 0.0])

        def put(part, q):
            q = np.asarray(q, float)
            n = P.poly_normal(q)
            ln = np.linalg.norm(n)
            if ln < 1e-10:
                return
            if n @ want < 0:
                q, n = q[::-1], -n
            part.add(q + n / ln * PILLAR_LIFT, 'paint')

        for i in range(len(rows) - 1):
            (a0, m0, c0), (a1, m1, c1) = rows[i], rows[i + 1]
            for q in ((m0, c0, c1), (m0, c1, m1)):
                put(fixed, q)
            for q in ((a0, m0, m1), (a0, m1, a1)):
                q = np.asarray(q, float)
                ins, outs = P.clip_poly(q, np.array([0.0, 0.0, 1.0]), zd + P.GAP / 2)   # behind the door's shut line: the door's
                if ins is not None and len(ins) >= 3:
                    put(door, ins)
                ins, outs = P.clip_poly(q, np.array([0.0, 0.0, -1.0]), -(zd - P.GAP / 2))   # ahead of it: the body's
                if ins is not None and len(ins) >= 3:
                    put(fixed, ins)


# --------------------------------------------------------------------------
# The car's own parts
# --------------------------------------------------------------------------
def _fittings(ctx):
    ctx.loft_tris = ctx.body_tris
    _skin_on(ctx)
    with T._on_skin(ctx):
        _fittings_on(ctx)


def _fittings_on(ctx):
    D, part, z, R = ctx.D, ctx.part, ctx.z, ctx.R
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']

    # ---- the bumpers, front and rear
    _bumper(ctx, 'bumper_f_band', 'front', BUMPER_F[0], BUMPER_F[1], BUMPER_PROUD)
    _bumper(ctx, 'bumper_r_band', 'rear', BUMPER_R[0], BUMPER_R[1], BUMPER_PROUD)

    # ---- the nose: square flush lamps in chrome bezels, the slot grille between them
    hx0, hx1, hy0, hy1 = HEAD
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        xa, xb = sorted((sx * hx0, sx * hx1))
        _plate(ctx, head, 'front', (xa - 0.006, hy0 - 0.006, xb + 0.006, hy1 + 0.006), 'plastic', 0.004)   # the housing
        _frame(ctx, head, 'front', (xa, hy0, xb, hy1), 0.011, 'chrome', 0.006)                               # the bezel
        _frame(ctx, head, 'front', (xa + 0.011, hy0 + 0.011, xb - 0.011, hy1 - 0.011), 0.009, 'glow_lens', 0.007)
        q = K.lay(ctx, head, 'front', K.rect2(xa + 0.020, hy0 + 0.020, xb - 0.020, hy1 - 0.020), 'glow_head', 0.008)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = K.lamp_centre(q)
        # amber blinkers on the bumper band, beside the plate
        x0, x1, y0, y1 = TURN_F
        xa, xb = sorted((sx * x0, sx * x1))
        tf = part('turn_f' + nm, bevel=0)
        _on_band(ctx, tf, 'front', (xa - 0.006, y0 - 0.006, xb + 0.006, y1 + 0.006), 'plastic', 0.0015)
        _on_band(ctx, tf, 'front', (xa, y0, xb, y1), 'glow_turn', 0.003)
    ghw, gy0, gy1 = GRILLE
    g = part('grille', bevel=0)
    _plate(ctx, g, 'front', (-ghw, gy0, ghw, gy1), 'rubber', 0.003, step=0.08)
    for k in range(2):
        yc = gy0 + (gy1 - gy0) * (k + 1) / 3
        _sd(ctx, g, 'front', (-ghw + 0.012, yc - 0.006, ghw - 0.012, yc + 0.006), 'plastic', 0.009)

    # ---- the tail: a lamp column each corner, ribbed; the roof-edge brake lamp; reversing lamps on the bumper
    lx0, lx1 = LAMP_X
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * lx0, sx * lx1))
        col = part('lamp_column_' + nm, bevel=0)
        # the housing in two, either side of the tail's ledge (a 3 cm step at 0.872-0.878: a wall across it chords it)
        _plate(ctx, col, 'rear', (xa - 0.008, COL_Y[0] - 0.008, xb + 0.008, LEDGE[0]), 'plastic', 0.003, step=0.12)
        _plate(ctx, col, 'rear', (xa - 0.008, LEDGE[1], xb + 0.008, COL_Y[1] + 0.008), 'plastic', 0.003, step=0.12)
        tr = part('turn_r' + nm, bevel=0)
        _sd(ctx, tr, 'rear', (xa, AMBER[0], xb, AMBER[1]), 'glow_turn', 0.0055)
        tl = part('tail_' + nm, bevel=0)
        _sd(ctx, tl, 'rear', (xa, TAIL_RED[0], xb, TAIL_RED[1]), 'glow_tail', 0.0055)
        q = P.laid_on(ctx.body_tris, 'rear', [(0.5 * (xa + xb), 0.5 * (TAIL_RED[0] + TAIL_RED[1]))], 0.0055)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = [float(v) for v in q[0]]
        _sd(ctx, part('brake_' + nm, bevel=0), 'rear', (xa, BRAKE[0], xb, BRAKE[1]), 'glow_brake', 0.0055)
        # the ribs: dark lines across the lenses every RIB, and the lens edges
        y = COL_Y[0] + RIB
        while y < COL_Y[1] - 0.02:
            _sd(ctx, col, 'rear', (xa - 0.002, y - 0.003, xb + 0.002, y + 0.003), 'plastic', 0.0075)
            y += RIB
        # reversing lamps on the bumper band
        x0, x1, y0, y1 = REVERSE
        xa, xb = sorted((sx * x0, sx * x1))
        rv = part('reverse_' + nm, bevel=0)
        _on_band(ctx, rv, 'rear', (xa - 0.006, y0 - 0.006, xb + 0.006, y1 + 0.006), 'plastic', 0.0015)
        _on_band(ctx, rv, 'rear', (xa, y0, xb, y1), 'glow_reverse', 0.003)
    cx0, cy0, cx1, cy1 = BRAKE_C
    hb = part('brake_c', bevel=0)
    _plate(ctx, hb, 'rear', (cx0 - 0.008, cy0 - 0.005, cx1 + 0.008, cy1 + 0.005), 'plastic', 0.004)
    _sd(ctx, hb, 'rear', (cx0, cy0, cx1, cy1), 'glow_brake', 0.0065)
    # the lamp over the rear plate, on the bumper band
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.band_tris['rear'], 'rear', [(0.0, pl_y + 0.020)], 0.012)
    if c is not None:
        P.obox(part('plate_lamp', bevel=0), c[0], (0.12, 0.018, 0.024), np.eye(3), 'plastic', {'-y': 'glow_lens'})

    # ---- the barn doors: a chrome pull each by the centre line; exposed hinges on the outer edges, the axis
    # along the door's sloped edge (HINGE_OUT outboard, HINGE_AFT behind the tail face), two knuckles each
    hinges = ctx.info.setdefault('hinges', {})
    z_axis = z(L) + HINGE_AFT
    for sx, nm in ((1, 'r'), (-1, 'l')):
        bh = part('handle_barn_' + nm, parent='hinge_barn_' + nm, bevel=0)
        xa, xb = sorted((sx * 0.03, sx * 0.14))
        _sd(ctx, bh, 'rear', (xa, 0.77, xb, 0.82), 'rubber', 0.002)
        grip = (xa + 0.012, 0.787, xb - 0.012, 0.803)
        _plate(ctx, bh, 'rear', grip, 'chrome', 0.011)
        door = ctx.parts['barn_' + nm]
        v = np.concatenate(door.polys)
        v = v[v[:, 0] * sx > 0]
        x_out = float(np.abs(v[:, 0]).max())
        x_axis = sx * (x_out + HINGE_OUT)
        hinges['hinge_barn_' + nm] = {'pos': [round(x_axis, 4), 0.72, round(float(z_axis), 4)], 'axis': [0, 1, 0],
                                      'open_sign': sx, 'open_deg': 100, 'panel': 'barn_' + nm}
        # two exposed hinges on the flat of the door: a strap from the door's edge back to a knuckle on the axis
        hp = part('barn_hinge_' + nm, parent='hinge_barn_' + nm, bevel=0)   # not 'hinge_*': the assembler reads those names as pivots
        for y_k in (0.64, 0.85):
            P.obox(hp, (x_axis - sx * HINGE_OUT / 2, y_k, z_axis - HINGE_AFT / 2 + 0.0005), (HINGE_OUT, 0.014, HINGE_AFT - 0.001), np.eye(3), 'plastic')
            K.cyl(hp, (x_axis, y_k - 0.025, z_axis), (x_axis, y_k + 0.025, z_axis), 0.006, 5, 'plastic')
    # a primer patch on the right barn door (the sheet's wear)
    patch = part('primer_patch', parent='hinge_barn_r', bevel=0)
    K.lay(ctx, patch, 'rear', [(0.24, 0.63), (0.42, 0.605), (0.51, 0.69), (0.47, 0.80), (0.33, 0.83), (0.22, 0.75)], 'paint_primer', 0.0008)

    # ---- the rub strip, over the arches: fender, door (on its hinge) and quarter pieces a side, each laid
    # in stretches between the plan's knots
    gap = P.GAP / 2 + 0.002
    for sx, nm in ((1, 'r'), (-1, 'l')):
        view = 'right' if sx > 0 else 'left'
        for a, b, pname in ((RUB_S[0], R['door_s0'] - gap, 'rub_fender_' + nm), (R['door_s0'] + gap, R['door_s1'] - gap, 'rub_door_' + nm),
                            (R['door_s1'] + gap, RUB_S[1], 'rub_quarter_' + nm)):
            pp = part(pname, parent='hinge_door_' + nm if pname.startswith('rub_door') else None, bevel=0)
            knots = [a] + [k_ for k_ in RUB_KNOTS if a + 0.02 < k_ < b - 0.02] + [b]
            for s0_, s1_ in zip(knots, knots[1:]):
                za, zb = sorted((z(s0_), z(s1_)))
                _plate(ctx, pp, view, (za, RUB_Y[0], zb, RUB_Y[1]), 'plastic', 0.006, step=0.14)
        # the ghost lettering above it, the door's word on the door
        _ghost(ctx, GHOST_DOOR[0], GHOST_DOOR[1], sx, part('ghost_door_' + nm, parent='hinge_door_' + nm, bevel=0))
        _ghost(ctx, GHOST_QUARTER[0], GHOST_QUARTER[1], sx, part('ghost_' + nm, bevel=0))
        _rust(ctx, sx)

    # ---- roof rails: the raised aluminium drip-rail gutter round the roof edge (on the loft's corner)
    rails = part('roof_rails', bevel=0)
    corner = lambda s, sx: np.array([sx * fcar.half_section(D, s)[0][8][0], fcar.half_section(D, s)[0][8][1], z(s)])
    f0, r0 = cab['W'] + 0.02, cab['R'] - 0.02
    for sx in (1, -1):
        a, b = corner(f0, sx), corner(r0, sx)
        P.obox(rails, (a + b) / 2 + np.array([0, RAIL_LIFT, 0]), (np.linalg.norm(b - a), 0.016, 0.02), P.frame_basis(b - a, (0, 1, 0)), 'chrome')
    for s_ in (f0, r0):
        a, b = corner(s_, -1), corner(s_, 1)
        P.obox(rails, (0.0, pl(D['top'], s_) + RAIL_LIFT - 0.002, z(s_)), (b[0] - a[0], 0.016, 0.02), np.eye(3), 'chrome')

    # ---- rear wiper, parked along the bottom of the right door's glass
    wp = part('wiper_rear', parent='hinge_barn_r', bevel=0)
    a = P.laid_on(ctx.body_tris, 'rear', [(0.10, 0.93)], 0.012)
    b = P.laid_on(ctx.body_tris, 'rear', [(0.50, 0.95)], 0.012)
    if a is not None and b is not None:
        a, b = a[0], b[0]
        P.obox(wp, (a + b) / 2, (np.linalg.norm(b - a), 0.014, 0.012), P.frame_basis(b - a, (0, 1, 0)), 'rubber')
        P.obox(wp, a + np.array([0.0, -0.02, 0.004]), (0.04, 0.04, 0.02), np.eye(3), 'plastic')

    # ---- fuel flap on the right rear quarter, over the strip (the tank is under the cargo floor)
    K.fuel_flap(ctx, 1, FLAP[0], FLAP[1], hh=0.05)

    # ---- brakes: the front caliper on the upright (the disc is in the wheel's mesh)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        hub_x = sx * (wh['track'] / 2 - wh['w'] / 2 - CALIPER_IN)
        P.obox(part('caliper_f' + nm, bevel=0), (hub_x, r_w + DISC_R - 0.035, z(axles[0])), (0.028, 0.07, 0.11), np.eye(3), 'steel')
    # ---- what shows of the running gear in the wells: the strut and its arm in front (behind the
    # well's inner wall, out to the upright), the torsion beam's trailing arm and the beam's end behind
    for sx, nm in ((1, 'r'), (-1, 'l')):
        sf = part('susp_f' + nm, bevel=0)
        K.cyl(sf, (sx * 0.42, r_w + 0.17, z(axles[0])), (sx * 0.40, r_w + 0.36, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        K.cyl(sf, (sx * (WELL_X + 0.004), r_w - 0.08, z(axles[0])), (sx * 0.56, r_w - 0.07, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))
        sr = part('susp_r' + nm, bevel=0)
        K.cyl(sr, (sx * 0.58, r_w + 0.03, z(axles[1] - 0.28)), (sx * 0.58, r_w, z(axles[1])), 0.022, 4, 'steel', caps=(False, False))
        K.cyl(sr, (sx * (WELL_X + 0.004), r_w - 0.02, z(axles[1] - 0.14)), (sx * 0.58, r_w - 0.02, z(axles[1] - 0.14)), 0.03, 5, 'steel', caps=(False, False))

    # ---- under the bonnet: the transverse four, its gearbox, the radiator, the battery
    en = part('engine', bevel=0)
    P.obox(en, (0.06, 0.56, z(0.52)), (0.62, 0.30, 0.36), np.eye(3), 'steel')
    P.obox(en, (0.06, 0.74, z(0.52)), (0.50, 0.06, 0.22), np.eye(3), 'plastic')
    P.obox(en, (-0.34, 0.50, z(0.50)), (0.18, 0.26, 0.26), np.eye(3), 'steel')     # the gearbox, clear of the strut
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.56, z(0.20)), (0.62, 0.34, 0.04), np.eye(3), 'rubber')
    P.obox(part('bay_battery', bevel=0), (0.30, 0.66, z(0.86)), (0.24, 0.18, 0.17), np.eye(3), 'plastic')   # inboard of the well wall

    # ---- antenna: one mast on the left front fender, its foot square to the fender's slope
    x, s_a = -0.80, 0.92
    on = lambda dx, dz: P.laid_on(ctx.body_tris, 'top', [(x + dx, z(s_a) + dz)], 0.0)
    pts = [on(0, 0), on(0, 0.01), on(0, -0.01), on(0.01, 0), on(-0.01, 0)]
    if all(q is not None for q in pts):
        b0, zp, zm, xp, xm = [np.asarray(q[0], float) for q in pts]
        nrm = np.cross(zp - zm, xp - xm)
        nrm = nrm / np.linalg.norm(nrm) * (1 if nrm[1] > 0 else -1)
        an = part('antenna', bevel=0)
        K.cyl(an, b0 - nrm * 0.0005, b0 + nrm * 0.010, 0.013, 6, 'plastic', caps=(False, True))
        K.cyl(an, b0 + nrm * 0.008, b0 + np.array([0.0, 0.42, 0.10]), 0.004, 3, 'rubber', caps=(False, False), r_b=0.002)

    # the door glass seal does not run on under the A-pillar strip (which lies over the glass edge)
    for nm in ('r', 'l'):
        seal = ctx.parts.get('seal_door_' + nm)
        if seal is None:
            continue
        keep = [i for i, q in enumerate(seal.polys)
                if not (q.mean(axis=0)[2] < z(cab['W']) and q.mean(axis=0)[1] > pl(D['belt'], R['door_s0']) + 0.02)]
        for attr in ('polys', 'mats', 'kind', 'shut'):
            setattr(seal, attr, [getattr(seal, attr)[i] for i in keep])

    _plates(ctx)
    T._wipers(ctx)
    _pivots(ctx)
    _pillar_legs(ctx)


def _pivots(ctx):
    """Hinge lines on the outside of each panel's edge (the tuner's rule): the
    doors on the outer skin at the front shut line, the hood on a gooseneck
    above and behind its rear edge, the fuel flap on its front edge."""
    D, R, z = ctx.D, ctx.R, ctx.z
    cab = D['cabin']
    H = ctx.info.setdefault('hinges', {})
    verts = lambda name: np.concatenate(ctx.parts[name].polys)
    v = verts('door_r')
    v = v[v[:, 0] > 0]
    zf = v[:, 2].min()
    near = v[v[:, 2] < zf + 0.03]
    x = float(near[:, 0].max()) + 0.001
    y = 0.5 * (R['door_y0'] + pl(D['belt'], R['door_s0']))
    for sx, nm in ((1, 'r'), (-1, 'l')):
        H['hinge_door_' + nm] = {'pos': [round(sx * x, 4), round(y, 4), round(float(zf) - 0.0005, 4)], 'axis': [0, 1, 0],
                                 'open_sign': sx, 'open_deg': 60, 'panel': 'door_' + nm}
    H['hinge_hood'] = {'pos': [0.0, round(float(pl(D['top'], cab['A']) + 0.01), 4), round(float(z(cab['A'] + 0.01)), 4)],
                       'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': 45, 'panel': 'hood'}
    v = verts('fuel_flap')
    h = H['hinge_fuel_flap']
    h['pos'] = [round(float(np.abs(v[:, 0]).max()) + 0.0005, 4), h['pos'][1], round(float(v[:, 2].min()) - 0.0005, 4)]


# --------------------------------------------------------------------------
# Wheels and anchors
# --------------------------------------------------------------------------
def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    if axle == 0:
        K.disc_brake(part, sx, tw, r=DISC_R)   # small solid discs in front (the caliper is a body part)
    else:
        K.drum(part, sx, tw, r=0.10)           # 200 mm drums at the rear
    if tag == WAGON_NO_CAP:
        # the sheet wheel's flat chrome cap comes off: bare steel and the wheel nuts
        keep = [i for i, m in enumerate(part.mats) if m != 'chrome']
        for name in ('polys', 'mats', 'kind', 'shut'):
            setattr(part, name, [getattr(part, name)[i] for i in keep])
        K.lug_nuts(part, sx, tw)
    else:
        K.hubcap(part, sx, tw, r=0.085, h=0.026)


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    A['bay_engine'] = {'pos': [0.06, 0.56, z(0.52)]}
    A['bay_radiator'] = {'pos': [0.0, 0.56, z(0.20)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A.pop('diff', None)                   # front drive: the diff is in the gearbox
    A['torsion_beam_r'] = {'pos': [0, D['wheel']['r'] - 0.02, z(fcar._axles(D)[1] - 0.14)]}
    A['spare_cradle'] = {'pos': [0.0, 0.215, z(4.02)]}   # where the spare hangs (not drawn: it crossed the floor)
    A['fuel_filler'] = {'pos': [pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'defn': {'well_x': WELL_X},
    'regions': {
        'nose_s': 0.14,                    # the snub nose panel, lamps and grille in it
        'hood_hw': 0.70,
        'tail_s': 3.75, 'tail_y': 0.54,    # the rear bumper, behind the arch and under the doors
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is two barn doors
    'no_antenna': True,                    # its own, on the left front fender
    'glass_panels': {'barn_l': 'glass_barn_l', 'barn_r': 'glass_barn_r'},   # each door carries its half of the rear glass
    'floors_to_body': True,                # a shut line's floor is the body's, not a sail's or a B-pillar's
    # the loft draws the backlight to the roof corners; outboard of the doors it is the lamp columns' pillar
    'glass_to_paint': lambda c: abs(c[0]) > BARN_HW and c[2] > 2.0,
    'hinge_of': {'barn_l': 'hinge_barn_l', 'barn_r': 'hinge_barn_r',
                 'glass_barn_l': 'hinge_barn_l', 'glass_barn_r': 'hinge_barn_r',
                 'pillar_a_door_l': 'hinge_door_l', 'pillar_a_door_r': 'hinge_door_r'},
    'plates': PLATES,
    'asymmetric': {
        'wiper_rear': 'one rear wiper, on the right barn door',
        'fuel_recess': 'one filler, on the right rear quarter',
        'fuel_flap': 'one filler, on the right rear quarter',
        'engine': 'a transverse engine: the gearbox hangs on its left end',
        'bay_battery': 'one battery, on the right',
        'exhaust': 'one tail pipe, on the left',
        'antenna': 'one mast, on the left front fender',
        'primer_patch': 'the primer patch is on the right barn door (the sheet)',
        'ghost_door_l': 'the ghost lettering reads left to right on both flanks, so the left is not the right\'s mirror',
        'ghost_door_r': 'the ghost lettering reads left to right on both flanks, so the left is not the right\'s mirror',
        'ghost_l': 'the ghost lettering reads left to right on both flanks, so the left is not the right\'s mirror',
        'ghost_r': 'the ghost lettering reads left to right on both flanks, so the left is not the right\'s mirror',
        'wheel_%s_mesh' % WAGON_NO_CAP: 'the sheet: one hubcap missing, left rear',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'solid disc 236 mm, single-pot caliper', 'rear': 'drum 200 mm'},
              'doors': 2, 'brake_lamps': 2, 'third_brake': 1, 'reverse': 2,
              'blinkers_front': 2, 'blinkers_rear': 2, 'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1,
              'wipers': 3, 'fuel_flap': 1, 'headlamps': 'square flush', 'condition': 0.6},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
