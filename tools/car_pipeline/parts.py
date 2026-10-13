"""Car modelling pipeline, the parts build (cars from parts, 2026-10-10): cut
one car's body loft into the parts a real car is made of and add the small
parts that sit on it. Numpy only; `build_car.py` turns the result into a scene
and writes it with either backend.

The shape does not change: the loft is `tools/fleet_design/car.py`'s, triangle
for triangle (checked on every build). What changes is what it is made of:

    body shell and cut panels   body, hood, door_l/r, trunk, fender_fl/fr,
                                bumper_f, bumper_r, underbody
    glass, seals, liners        glass_*, seal_*, pillar_a_l/r, pillar_b_l/r,
                                sail_l/r, arch_liner_fl/fr/rl/rr
    lamps, grille, mirrors      grille, turn_l/r, popup_l/r (pod + lens + bulb),
                                tail_l/r (red lens over the glow), tail_panel,
                                mirror_l/r, handle_l/r
    small parts                 plate_f/r, wiper_l/r, antenna, spoiler, exhaust,
                                bumper_r_insert

Shut lines. A panel is cut out with planes; every cut leaves a real gap of
GAP (4 mm): each side is trimmed GAP/2 back from the nominal line. A panel
that opens turns its edge in RETURN (15 mm) deep; the fixed side carries a
dark floor at that depth, reaching under both edges, so a gap is never a hole
into the car. A shut line has to read from a chase camera where 4 mm is less
than a pixel, so every vertex also carries `shut`: 1 on the edge, falling to 0
over BAND (6 mm) of skin on each side; the paint shader darkens by it.

Symmetry (Roy, 2026-10-10: "make sure the cars are symmetrical"). Only the
right half of the car is kept from everything built here; the left half is its
mirror image, vertex for vertex. A part that straddles the centre line (hood,
body, bumpers, windshield...) holds its right half and is marked `centre`; a
right-hand part (door_r, fender_fr, tail_r...) is marked `pair` and its left
twin is written as its mirror. The only parts that are not mirrored are the
ones in ASYMMETRIC, each for a reason given there.

Everything is kept as convex polygons until it is written, so a cut adds one
vertex where it crosses an edge and nothing else. Per polygon: a material name
and a `kind` (SKIN can take a crease bevel, WALL/FLOOR/DETAIL never do). Per
vertex: `shut`.
"""
import math

import numpy as np

import types

import car as fcar
from geom import AXES, Mesh, box, pl, place_on_surface

GAP = 0.004        # shut gap, metres (3.5-4.5 mm; never over 5)
RETURN = 0.015     # how deep a panel edge turns in behind the gap
BAND = 0.006       # width of the dark vertex-colour band on each side
FLOOR_IN = 0.025   # the gap floor reaches this far under its own side's skin
FLOOR_OUT = 0.008  # and this far under the panel across the gap
SEAL_W = 0.012     # rubber seal round a glass
SEAL_LIFT = 0.0015
LIP = 0.018        # rolled-in wheel arch edge
EPS = 1e-7
ON_PLANE = 2.5e-4

SKIN, WALL, FLOOR, DETAIL = 0, 1, 2, 3

# The parts that are NOT mirror images left to right, and why.
ASYMMETRIC = {
    'mirror_l': "door mirrors: the game aims the two cups differently at the driver (P1CoupeBuilder.MIRRORS yaw 12 / -20)",
    'mirror_r': "door mirrors: the game aims the two cups differently at the driver (P1CoupeBuilder.MIRRORS yaw 12 / -20)",
    'wiper_l': "wipers park the same way round on both sides, as on a real car",
    'wiper_r': "wipers park the same way round on both sides, as on a real car",
    'antenna': "one mast, on the left rear quarter",
}

# fleet material -> parts-build material (the names CarAssembler keys on)
MATMAP = {'paint': 'paint', 'roof': 'paint', 'under': 'under_paint', 'glass': 'glass',
          'pillar': 'plastic', 'trim': 'plastic', 'grille': 'rubber', 'chrome': 'chrome',
          'exh_hole': 'rubber', 'head': 'glow_head', 'tail': 'glow_tail', 'turn': 'glow_turn',
          'primer': 'paint_primer', 'paint2': 'paint_primer', 'rust': 'paint_rust', 'bondo': 'paint_bondo',
          'tire': 'rubber', 'tire_side': 'rubber', 'rim': 'rim', 'rim_bronze': 'rim', 'rim_dark': 'steel',
          'interior': 'plastic'}    # the tub of an open car (the kei): its walls and floor
COLOURS = {
    'paint': None,                 # the car's own paint
    'under_paint': '#0B0D12',      # behind the shut lines, the underbody
    'plastic': None,               # the car's trim colour
    'chrome': '#C9CED6',
    'rubber': '#08090C',
    'plate': '#E9E6DF',
    'mirror': '#9AA3B2',
    'lens_red': '#A3161B',
    'glass': '#151D2E',
    'glow_head': '#FFE7BD',
    'glow_lens': '#8A7350',        # the lamp lens round the bulb: the same warm white, dimmer
    'glow_tail': '#E5262B',
    'glow_turn': '#FFC066',
    # separate lamps that are dark until the game lights them (Roy 1171-1180)
    'glow_brake': '#7A1418',
    'glow_reverse': '#3A3A38',
    # fixed paints: a panel that is not the car's colour (primer, rust, filler)
    'paint_primer': None,
    'paint_rust': None,
    'paint_bondo': None,
    'steel': '#4A4E55',            # drums, discs, axles, engine castings
    'rim': None,                   # the wheel's own rim colour
}
# parts-build material -> the fleet colour it takes when COLOURS has None
ALIAS = {'plastic': 'trim', 'paint_primer': 'primer', 'paint_rust': 'rust', 'paint_bondo': 'bondo'}


def kit_of(D):
    """What one car adds to the common recipe (kits.KITS), or {}."""
    import kits
    return kits.KITS.get(D['id'], {})


def poly_normal(p):
    """Newell normal (not normalised): twice the area along the normal."""
    q = np.roll(p, -1, axis=0)
    return np.array([((p[:, 1] - q[:, 1]) * (p[:, 2] + q[:, 2])).sum(),
                     ((p[:, 2] - q[:, 2]) * (p[:, 0] + q[:, 0])).sum(),
                     ((p[:, 0] - q[:, 0]) * (p[:, 1] + q[:, 1])).sum()])


def _tri_area2(a, b, c):
    return float(np.linalg.norm(np.cross(b - a, c - a)))


def triangulate(poly, vals=None):
    """Convex polygon -> triangles [(3,3)], and the per-corner values with them.
    Fans from the corner that leaves the fattest triangles; a polygon with a
    vertex in the middle of every edge is fanned from its centre instead."""
    k = len(poly)
    vals = np.zeros(k) if vals is None else np.asarray(vals, float)
    if k == 3:
        return [poly], [vals]
    best = None
    for a in range(k):
        idx = [(a, (a + i) % k, (a + i + 1) % k) for i in range(1, k - 1)]
        m = min(_tri_area2(poly[i], poly[j], poly[l]) for i, j, l in idx)
        if best is None or m > best[0]:
            best = (m, idx)
    if best[0] > 1e-9:
        return [poly[list(t)] for t in best[1]], [vals[list(t)] for t in best[1]]
    c, cv = poly.mean(axis=0), float(vals.mean())
    tris, tv = [], []
    for i in range(k):
        j = (i + 1) % k
        if _tri_area2(c, poly[i], poly[j]) > 1e-10:
            tris.append(np.array([c, poly[i], poly[j]]))
            tv.append(np.array([cv, vals[i], vals[j]]))
    return tris, tv


class Part:
    """One named mesh: convex polygons in car space (the scene builder moves
    the ones under a hinge into the hinge's frame)."""

    def __init__(self, name, parent=None, bevel=None):
        self.name = name
        self.parent = parent      # hinge node name, or None for the car root
        self.bevel = bevel        # crease bevel width override (metres); 0 = none, None = the car's rule
        self.sym = None           # 'centre': polys are the right half, the mesh is that plus its mirror;
        #                           'pair': a right-hand part, `twin` is the left one, written as its mirror;
        #                           None: written as it is (ASYMMETRIC)
        self.twin = None
        self.polys = []           # (k,3) arrays, counter-clockwise seen from outside
        self.mats = []
        self.kind = []
        self.shut = []            # (k,) per polygon

    def add(self, poly, mat, kind=DETAIL, shut=None):
        poly = np.asarray(poly, float)
        if len(poly) < 3 or np.linalg.norm(poly_normal(poly)) < 1e-10:
            return
        self.polys.append(poly)
        self.mats.append(mat)
        self.kind.append(kind)
        self.shut.append(np.zeros(len(poly)) if shut is None else np.asarray(shut, float))

    def quad(self, a, b, c, d, mat, kind=DETAIL):
        self.add((a, b, c), mat, kind)
        self.add((a, c, d), mat, kind)

    def tris(self):
        """-> T (n,3,3), mats [n], kind [n], shut (n,3)."""
        T, M, K, S = [], [], [], []
        for poly, mat, kind, shut in zip(self.polys, self.mats, self.kind, self.shut):
            tt, vv = triangulate(poly, shut)
            T += tt
            S += vv
            M += [mat] * len(tt)
            K += [kind] * len(tt)
        return np.array(T).reshape(-1, 3, 3), M, K, np.array(S).reshape(-1, 3)

    def tri_count(self):
        return sum(len(p) - 2 for p in self.polys) * (2 if self.sym == 'centre' else 1)

    def __len__(self):
        return len(self.polys)


# --------------------------------------------------------------------------
# The loft, with what each triangle is (strip, side, station)
# --------------------------------------------------------------------------
def loft_tagged(D):
    """fleet_design.car.loft(D), plus a tag per triangle:
    (strip 0..9 or -1 front cap / -2 rear cap, side +1/-1/0, station index)."""
    N = fcar.N_HALF
    sts = fcar.stations(D)
    rings, infos = [], []
    for s in sts:
        P, info = fcar.half_section(D, s)
        z = fcar._s2z(D, s)
        right = [np.array([x, y, z]) for x, y in P]
        left = [np.array([-x, y, z]) for x, y in P[1:N - 1]][::-1]
        rings.append(right + left)
        infos.append(info)
    n = len(rings[0])

    def strip_of(k):
        if k <= 9:
            return k
        if k <= 18:
            return 19 - k
        return 0

    tris, mats, tags = [], [], []

    def tri(a, b, c, mat, tag):
        if np.linalg.norm(np.cross(b - a, c - a)) < 1e-9:
            return
        tris.append(np.array([a, b, c]))
        mats.append(mat)
        tags.append(tag)

    a, b = rings[len(rings) // 2], rings[len(rings) // 2 + 1]
    flip = np.cross(a[5] - a[4], b[5] - a[4])[0] < 0
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        smid = 0.5 * (sts[i] + sts[i + 1])
        info = infos[i] if 'open' in infos[i] and 'open' in infos[i + 1] else {}
        for k in range(n):
            k2 = (k + 1) % n
            j = strip_of(k)
            mat = fcar._strip_mat(D, j, smid, info)
            tag = (j, 1 if k <= 9 else -1, i)
            q = (a[k], b[k], b[k2], a[k2]) if flip else (a[k], a[k2], b[k2], b[k])
            tri(q[0], q[1], q[2], mat, tag)
            tri(q[0], q[2], q[3], mat, tag)
    for ring, want, capj in ((rings[0], -1.0, -1), (rings[-1], 1.0, -2)):
        c = sum(ring) / len(ring)
        cap = [(c, ring[k], ring[(k + 1) % n]) for k in range(n)]
        real = [t for t in cap if np.linalg.norm(np.cross(t[1] - t[0], t[2] - t[0])) >= 1e-9]
        if real and np.cross(real[0][1] - real[0][0], real[0][2] - real[0][0])[2] * want < 0:
            cap = [(c, ring[(k + 1) % n], ring[k]) for k in range(n)]
        for t in cap:
            tri(t[0], t[1], t[2], 'paint', (capj, 0, 0 if capj == -1 else len(rings) - 2))
    T = np.array(tris)
    ref = fcar.loft(D)[0].array()
    if T.shape != ref.shape or np.abs(T - ref).max() > 1e-12:
        raise SystemExit('parts.loft_tagged no longer matches fleet_design.car.loft: the shape would change')
    return T, mats, tags, sts


def merge_flat(D, ps, sts, tol=3e-3):
    """Kit option `merge_flat`. The loft has a ring of triangles at every
    station, and a wheel arch alone puts nine stations across the whole car:
    the roof, the hood and the floor are cut into slivers there although they
    are flat. Merge each run of quads along one strip whose long edges are
    straight lines into one quad, as long as its fourth corner stays within
    `tol` (3 mm) of the plane of the other three: the skin then moves by less
    than half of that, and only between the long edges, which do not move.
    The outline of the car is the sheet's; a neighbour strip that keeps its
    stations gets them back as points on the shared edge (fix_tjunctions)."""
    ring = [[np.array([x, y, fcar._s2z(D, s)]) for x, y in fcar.half_section(D, s)[0]] for s in sts]
    by = {}
    for idx, g in enumerate(ps.G):
        if g[0] >= 0 and g[1] != 0:
            by.setdefault((g[0], g[1], g[2]), []).append(idx)

    def straight(i, k):
        a, b, c = ring[i - 1][k], ring[i][k], ring[i + 1][k]
        t = (sts[i] - sts[i - 1]) / (sts[i + 1] - sts[i - 1])
        return np.abs(a + (c - a) * t - b).max() < 1e-7

    def quad(j, side, i, k):
        q = np.array([ring[i][j], ring[i][j + 1], ring[k + 1][j + 1], ring[k + 1][j]])
        return q * MIRROR if side < 0 else q

    def bend(q):
        n = np.cross(q[1] - q[0], q[2] - q[0])
        ln = np.linalg.norm(n)
        return abs((q[3] - q[0]) @ n) / ln if ln > 1e-12 else 1.0

    n_int = len(sts) - 1
    drop, add = set(), []
    for j in range(fcar.N_HALF - 1):
        for side in (1, -1):
            i = 0
            while i < n_int:
                first = by.get((j, side, i))
                if not first or len(first) != 2:
                    i += 1
                    continue
                mat = ps.M[first[0]]
                k = i
                while k + 1 < n_int:
                    nxt = by.get((j, side, k + 1))
                    if not nxt or len(nxt) != 2 or ps.M[nxt[0]] != mat or ps.M[nxt[1]] != mat:
                        break
                    if not (straight(k + 1, j) and straight(k + 1, j + 1)) or bend(quad(j, side, i, k + 1)) > tol:
                        break
                    k += 1
                if k > i and ps.M[first[1]] == mat:
                    q = quad(j, side, i, k)
                    idx = [t for m in range(i, k + 1) for t in by[(j, side, m)]]
                    want = sum(poly_normal(ps.P[t]) for t in idx)
                    add.append((q if poly_normal(q) @ want > 0 else q[::-1], mat, (j, side, i)))
                    drop.update(idx)
                i = k + 1
    out = ps.pick([t not in drop for t in range(len(ps))])
    for q, mat, tag in add:
        out.add(q, mat, tag)
    return out


# --------------------------------------------------------------------------
# Polygon sets
# --------------------------------------------------------------------------
class PolySet:
    def __init__(self, P=None, M=None, G=None):
        self.P = list(P) if P is not None else []     # (k,3) arrays
        self.M = list(M) if M is not None else []     # fleet material names
        self.G = list(G) if G is not None else []     # tags (strip, side, station)

    def __len__(self):
        return len(self.P)

    def pick(self, mask):
        idx = [i for i, m in enumerate(mask) if m]
        return PolySet([self.P[i] for i in idx], [self.M[i] for i in idx], [self.G[i] for i in idx])

    def extend(self, other):
        self.P += other.P
        self.M += other.M
        self.G += other.G
        return self

    def add(self, poly, mat, tag):
        self.P.append(poly)
        self.M.append(mat)
        self.G.append(tag)

    def col(self, k):
        return np.array([g[k] for g in self.G], int)

    def mat_is(self, name):
        return np.array([m == name for m in self.M], bool)

    def centroids(self):
        return np.array([p.mean(axis=0) for p in self.P]).reshape(-1, 3)


def clip_poly(pts, n, d):
    """Convex polygon against the plane n.p >= d -> (inside or None, outside or None)."""
    dist = pts @ n - d
    dist[np.abs(dist) < EPS] = 0.0
    if (dist <= 0).all():
        return None, pts
    if (dist >= 0).all():
        return pts, None
    ins, outs = [], []
    k = len(pts)
    for i in range(k):
        a, da = pts[i], dist[i]
        b, db = pts[(i + 1) % k], dist[(i + 1) % k]
        if da >= 0:
            ins.append(a)
        if da <= 0:
            outs.append(a)
        if (da > 0 > db) or (da < 0 < db):
            p = a + (b - a) * (da / (da - db))
            ins.append(p)
            outs.append(p)

    def ok(q):
        if len(q) < 3:
            return None
        q = np.array(q)
        return q if np.linalg.norm(poly_normal(q)) > 1e-10 else None
    return ok(ins), ok(outs)


def clip(ps, n, d):
    """Split a polygon set by the plane n.p >= d -> (inside, outside)."""
    n = np.asarray(n, float)
    a, b = PolySet(), PolySet()
    for poly, mat, tag in zip(ps.P, ps.M, ps.G):
        i, o = clip_poly(poly, n, d)
        if i is not None:
            a.add(i, mat, tag)
        if o is not None:
            b.add(o, mat, tag)
    return a, b


def take(pool, planes, mask):
    """Cut the convex region (all planes n.p >= d) out of the masked part of the
    pool, leaving a GAP wide shut line all round: the part is trimmed GAP/2
    inside each plane, what is left GAP/2 outside. -> (part, rest)."""
    m = mask(pool) if mask is not None else np.ones(len(pool), bool)
    cand, rest = pool.pick(m), pool.pick(~np.asarray(m, bool))
    part = cand
    for n, d in planes:
        part, _ = clip(part, n, d + GAP / 2)
    left = cand
    for n, d in planes:
        left, out = clip(left, n, d - GAP / 2)
        rest.extend(out)
    return part, rest


def weld(polys, eps=1e-5):
    """-> (verts (v,3), loops: one index list per polygon)."""
    if not polys:
        return np.zeros((0, 3)), []
    flat = np.concatenate(polys)
    keys = np.round(flat / eps).astype(np.int64)
    uniq, inv = np.unique(keys, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    verts = np.zeros((len(uniq), 3))
    np.add.at(verts, inv, flat)
    verts /= np.bincount(inv, minlength=len(uniq))[:, None]
    loops, at = [], 0
    for p in polys:
        loops.append([int(v) for v in inv[at:at + len(p)]])
        at += len(p)
    return verts, loops


def boundary_edges(loops):
    """Directed edges (a, b, polygon) that only one polygon uses."""
    count = {}
    for pi, loop in enumerate(loops):
        k = len(loop)
        for i in range(k):
            a, b = loop[i], loop[(i + 1) % k]
            if a == b:
                continue
            count.setdefault((min(a, b), max(a, b)), []).append((a, b, pi))
    return [v[0] for v in count.values() if len(v) == 1]


def fix_tjunctions(ps, rounds=4):
    """A cut that stops inside the mesh leaves a vertex in the middle of its
    neighbour's edge. Put that vertex into the neighbour's outline so every
    edge is shared again."""
    for _ in range(rounds):
        verts, loops = weld(ps.P)
        be = boundary_edges(loops)
        if not be:
            return ps
        bverts = np.array(sorted({a for a, _, _ in be} | {b for _, b, _ in be}))
        P = verts[bverts]
        ins = {}
        for a, b, pi in be:
            A, B = verts[a], verts[b]
            ab = B - A
            L2 = float(ab @ ab)
            if L2 < 1e-12:
                continue
            t = (P - A) @ ab / L2
            off = np.linalg.norm((P - A) - np.outer(t, ab), axis=1)
            hit = np.nonzero((t > 1e-4) & (t < 1 - 1e-4) & (off < 2e-5))[0]
            if len(hit):
                ins.setdefault(pi, []).append((a, b, [(float(t[h]), P[h]) for h in hit]))
        if not ins:
            return ps
        for pi, items in ins.items():
            loop, poly = loops[pi], ps.P[pi]
            out = []
            k = len(loop)
            for i in range(k):
                out.append(poly[i])
                a, b = loop[i], loop[(i + 1) % k]
                for ea, eb, pts in items:
                    if ea == a and eb == b:
                        out += [p for _, p in sorted(pts, key=lambda q: q[0])]
            ps.P[pi] = np.array(out)
    return ps


# --------------------------------------------------------------------------
# Shut lines: band, edge return, floor
# --------------------------------------------------------------------------
def shut_edges(ps, planes):
    """Boundary edges of the set that lie on one of its shut planes.
    planes: [(n, d, wall, floor)] with n pointing into the part.
    -> verts, loops, [(a, b, polygon, plane index)]"""
    verts, loops = weld(ps.P)
    out = []
    for a, b, pi in boundary_edges(loops):
        for k, pl_ in enumerate(planes):
            n, d = pl_[0], pl_[1]
            if abs(verts[a] @ n - d) < ON_PLANE and abs(verts[b] @ n - d) < ON_PLANE:
                out.append((a, b, pi, k))
                break
    return verts, loops, out


def add_bands(ps, planes):
    """Split the skin BAND inside every shut edge, so the dark band is BAND
    wide whatever the polygon size. Only polygons near the edge are cut."""
    verts, _, edges = shut_edges(ps, planes)
    boxes = []
    for k, pl_ in enumerate(planes):
        n, d = pl_[0], pl_[1]
        pts = [verts[a] for a, _, _, p in edges if p == k] + [verts[b] for _, b, _, p in edges if p == k]
        if not pts:
            boxes.append(None)
            continue
        pts = np.array(pts)
        lo, hi = pts.min(0) - 0.012, pts.max(0) + 0.012
        boxes.append((lo, hi))
        near = np.array([bool(((p.max(0) >= lo) & (p.min(0) <= hi)).all()) for p in ps.P], bool)
        a, b = clip(ps.pick(near), n, d + BAND)
        ps = ps.pick(~near).extend(a).extend(b)
    return fix_tjunctions(ps), boxes


def shut_values(P, planes, boxes):
    """`shut` for points P (m,3): 1 on a shut edge, 0 BAND inside it."""
    P = np.asarray(P, float).reshape(-1, 3)
    val = np.zeros(len(P))
    for pl_, bx in zip(planes, boxes):
        if bx is None:
            continue
        lo, hi = bx
        dist = P @ np.asarray(pl_[0], float) - pl_[1]
        inside = ((P >= lo) & (P <= hi)).all(axis=1) & (dist > -ON_PLANE)
        v = np.clip(1.0 - dist / BAND, 0.0, 1.0)
        val = np.where(inside, np.maximum(val, v), val)
    return val


def finish_shut(ps, planes):
    """Bands, edge returns and gap floors for one cut set.
    -> list of (polygon, material, kind, shut(k), tag)."""
    ps, boxes = add_bands(ps, planes)
    out = [(p, m, SKIN, shut_values(p, planes, boxes), g) for p, m, g in zip(ps.P, ps.M, ps.G)]
    verts, loops, edges = shut_edges(ps, planes)
    if not edges:
        return out
    pn = np.array([poly_normal(p) for p in ps.P])
    vn = np.zeros_like(verts)
    for loop, n in zip(loops, pn):
        for v in loop:
            vn[v] += n
    # a vertex on the centre line only sees its right-hand faces here: keep its
    # normal in the centre plane, so the edge return meets its mirror image
    vn[np.abs(verts[:, 0]) < 1e-6, 0] = 0.0
    ln = np.linalg.norm(vn, axis=1)
    ln[ln < 1e-12] = 1.0
    vn /= ln[:, None]
    on = {}
    for a, b, _, k in edges:
        on.setdefault(a, set()).add(k)
        on.setdefault(b, set()).add(k)

    def inward(v):
        """Direction an edge turns in at vertex v: into the body, inside the cut plane(s)."""
        w = -vn[v]
        for k in on[v]:
            n = planes[k][0]
            w = w - n * (w @ n)
        ln = np.linalg.norm(w)
        return w / ln if ln > 1e-6 else -vn[v]

    def wound(q, want):
        q = np.array(q)
        return q if poly_normal(q) @ want > 0 else q[::-1]

    for a, b, pi, k in edges:
        n, _, wall, floor = planes[k]
        A, B = verts[a], verts[b]
        da, db = inward(a) * RETURN, inward(b) * RETURN
        tag = ps.G[pi]
        if wall:
            wm = ps.M[pi] if ps.M[pi] in ('paint', 'roof', 'primer') else 'rubber'
            out.append((wound([A, B, B + db, A + da], -n), wm, WALL, np.ones(4), tag))
        if floor:
            q = [A + da + n * FLOOR_IN, B + db + n * FLOOR_IN,
                 B + db - n * (GAP + FLOOR_OUT), A + da - n * (GAP + FLOOR_OUT)]
            out.append((wound(q, pn[pi]), 'under', FLOOR, np.ones(4), tag))
    return out


# --------------------------------------------------------------------------
# Small helpers for the bolted-on parts
# --------------------------------------------------------------------------
def facing(tris, direction):
    """Wind every polygon so its normal has a positive component along direction."""
    out = []
    d = np.asarray(direction, float)
    for t in tris:
        t = np.asarray(t, float)
        out.append(t if poly_normal(t) @ d >= 0 else t[::-1])
    return out


def obox(part, center, size, basis, mat, mats=None, kind=DETAIL):
    """A box with its own axes (basis columns = its x, y, z in car space)."""
    m = Mesh()
    box(m, (0, 0, 0), size, mat, mats)
    c = np.asarray(center, float)
    B = np.asarray(basis, float)
    for t, mm in zip(m.tris, m.mats):
        part.add(np.array([c + B @ p for p in t]), mm, kind)


def yaw_basis(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])   # Godot's Basis(Vector3.UP, a)


def frame_basis(x_dir, up_hint):
    """Orthonormal basis with x along x_dir and y as close to up_hint as it gets."""
    x = np.asarray(x_dir, float)
    x = x / np.linalg.norm(x)
    y = np.asarray(up_hint, float)
    y = y - x * (y @ x)
    y = y / np.linalg.norm(y)
    return np.column_stack([x, y, np.cross(x, y)])


def laid_on(body_tris, view, pts2d, offset):
    """Points projected onto the body along a view axis, `offset` proud of it."""
    return place_on_surface(body_tris, view, pts2d, offset=offset)


def decal(part, D, body_tris, d, mat, offset, kind=DETAIL):
    """A fleet decal (rect, circle, poly) laid on the body as this part."""
    m = fcar.CarModel(D)
    dd = dict(d)
    dd['mat'] = mat
    dd['offset'] = offset
    fcar.add_decal(m, body_tris, dd)
    out = -AXES[d['view']]
    for t in m.mesh.tris:
        part.add(facing([t], out)[0], mat, kind)


# --------------------------------------------------------------------------
# The car
# --------------------------------------------------------------------------
def regions(D):
    """Where the panels are cut (s along the length from the nose, metres)."""
    cab = D['cabin']
    R = dict(kit_of(D).get('regions') or {})
    R.update(D.get('part_regions') or {})
    pillars = cab.get('pillars') or [[cab['A'] + 1.1, cab['A'] + 1.16]]
    hw_mid = pl(D['hw'], 0.5 * (cab['A'] + cab['W']))
    R.setdefault('nose_s', 0.55)                               # bumper / hood / fender line
    R.setdefault('hood_hw', min(0.70, hw_mid - 0.17))
    R.setdefault('door_s0', cab['A'] + 0.04)
    R.setdefault('door_s1', pillars[0][0])
    R.setdefault('door_y0', D.get('rocker_h', 0.3) + 0.06)
    R.setdefault('trunk_s0', cab['C'] + 0.03)
    R.setdefault('trunk_s1', D['L'] - 0.15)
    R.setdefault('trunk_hw', min(0.66, pl(D['hw'], cab['C'] + 0.03) - 0.2))
    R.setdefault('tail_s', 3.90)                               # rear bumper starts behind the rear arch
    R.setdefault('tail_y', 0.36)                               # and stays below the tail panel
    return R


HINGE_OF = {'hood': 'hinge_hood', 'trunk': 'hinge_trunk', 'door_l': 'hinge_door_l', 'door_r': 'hinge_door_r',
            'glass_door_l': 'hinge_door_l', 'glass_door_r': 'hinge_door_r'}
CUT_PARTS = ('body', 'hood', 'door_l', 'door_r', 'trunk', 'fender_fl', 'fender_fr', 'bumper_f', 'bumper_r')


def build_parts(D, tips_out=None):
    """-> (parts list, info dict). D is a resolved fleet definition."""
    kit = kit_of(D)
    if kit.get('defn'):
        D = dict(D, **kit['defn'])                # the kit's own changes to the loft (the tuner's deeper wheel wells)
    cab = D['cabin']
    panel_mats = kit.get('panel_mats', {})
    z = lambda s: fcar._s2z(D, s)
    s_of = lambda p: p[2] + D['OHf'] + D['WB'] / 2.0
    R = regions(D)
    T, M, G, sts = loft_tagged(D)
    body_tris = T.copy()
    pool = PolySet(list(T), M, G)
    if kit.get('merge_flat'):
        pool = merge_flat(D, pool, sts)
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    axles = fcar._axles(D)

    sets = {}           # name -> (PolySet, planes)
    rest_planes = []

    def cut(name, planes, mask, opens, owns=None):
        """opens: the part is a panel that opens (it gets the edge returns, the
        other side the floor). owns: per plane, a fixed part that carries the
        floor of that line (the other side then carries nothing)."""
        nonlocal pool
        owns = owns or [False] * len(planes)
        part, pool = take(pool, planes, mask)
        sets[name] = (part, [(np.asarray(n, float), d + GAP / 2, opens, o) for (n, d), o in zip(planes, owns)])
        for (n, d), o in zip(planes, owns):
            rest_planes.append((-np.asarray(n, float), -(d - GAP / 2), False, opens or not o))

    # the underside first: it is not cut by the panels
    j = pool.col(0)
    is_under = (j >= 0) & (j <= 2)
    under, pool = pool.pick(is_under), pool.pick(~is_under)

    top = lambda ps: (ps.col(0) >= 8) & ~ps.mat_is('glass')
    hw_, s0, s1 = R['hood_hw'], R['nose_s'], cab['A']
    cut('hood', [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((1, 0, 0), -hw_), ((-1, 0, 0), -hw_)], top, True)
    hw_, s0, s1 = R['trunk_hw'], R['trunk_s0'], R['trunk_s1']
    if kit.get('no_trunk'):
        sets['trunk'] = (PolySet(), [])          # no deck lid: the kit cuts its own tail doors
    else:
        cut('trunk', [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((1, 0, 0), -hw_), ((-1, 0, 0), -hw_)], top, True)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 3) & (ps.col(0) <= 7))(sx)
        cut('door_' + nm, [((0, 0, 1), z(R['door_s0'])), ((0, 0, -1), -z(R['door_s1'])), ((0, 1, 0), R['door_y0'])],
            side, True)
    everything = lambda ps: np.ones(len(ps), bool)
    # the nose: it carries the floor against the hood and both fenders
    cut('bumper_f', [((0, 0, -1), -z(R['nose_s']))], everything, False, [True])
    cut('bumper_r', [((0, 0, 1), z(R['tail_s'])), ((0, -1, 0), -R['tail_y'])], everything, False, [True, True])
    extra_cuts = []
    if kit.get('cuts'):
        # the kit's own panels: f(D, R, z, cut) -> the names it cut
        extra_cuts = list(kit['cuts'](D, R, z, cut))
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: ~ps.mat_is('glass') & (ps.centroids()[:, 0] * sx > 0))(sx)
        cut('fender_f' + nm, [((0, 0, 1), z(R['nose_s'])), ((0, 0, -1), -z(R['door_s0'])), ((sx, 0, 0), R['hood_hw'])],
            side, False, [False, True, True])
    sets['body'] = (pool, rest_planes)

    def piece_of(name, mat, tag, cen):
        """Which glTF node a body or door polygon ends up in."""
        lr = 'r' if cen[0] > 0 else 'l'
        if name.startswith('door_'):
            return ('glass_' + name) if mat == 'glass' else name   # door_l -> glass_door_l, a kit's door_rr -> glass_door_rr
        if name != 'body':
            return name
        if mat == 'glass':
            if tag[0] >= 8:
                if s_of(cen) < 0.5 * (cab['W'] + cab['R']):
                    return 'glass_windshield'
                # tail doors (kit): each carries its half of the rear glass
                return ('glass_barn_' + lr) if kit.get('split_backlight') else 'glass_backlight'
            return ('sail_' if s_of(cen) < R['door_s0'] else 'glass_quarter_') + lr
        if mat == 'pillar':
            return 'pillar_b_' + lr
        return 'body'

    # kit: stretches of the side skin in another paint (a primer fender). The
    # skin is split on the region's edges and keeps its place, so nothing is
    # laid over it and no shut line is added.
    for s0, s1, y0, y1, mat in kit.get('paint_regions', []):
        box_ = [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((0, 1, 0), y0), ((0, -1, 0), -y1)]
        for name in list(CUT_PARTS) + extra_cuts:
            ps, planes = sets[name]
            m = ps.mat_is('paint') & (ps.col(0) >= 3) & (ps.col(0) <= 7)
            ins, rest = ps.pick(m), ps.pick(~m)
            for n, d in box_:
                ins, out = clip(ins, n, d)
                rest.extend(out)
            ins.M = [mat] * len(ins)
            sets[name] = (rest.extend(ins), planes)

    parts = {}

    hinge_of = dict(HINGE_OF)
    hinge_of.update(kit.get('hinge_of', {}))

    def part(name, parent=None, bevel=None):
        if name not in parts:
            parts[name] = Part(name, parent if parent is not None else hinge_of.get(name), bevel)
        return parts[name]

    counts = {}
    for name in list(CUT_PARTS) + extra_cuts:
        ps, planes = sets[name]
        rows = finish_shut(ps, planes)
        counts[name] = {'wall': sum(len(r[0]) - 2 for r in rows if r[2] == WALL),
                        'floor': sum(len(r[0]) - 2 for r in rows if r[2] == FLOOR)}
        for poly, mat, kind, shut, tag in rows:
            pn = piece_of(name, mat if kind == SKIN else _skin_mat(tag, D, sts), tag, poly.mean(axis=0))
            m = MATMAP.get(mat, mat)
            if pn.startswith('sail_') and kind == SKIN:
                m = 'plastic'
            if m == 'paint' and pn in panel_mats:
                m = panel_mats[pn]
            part(pn).add(poly, m, kind, shut)

    # underbody and the arch liners
    for poly, tag in zip(under.P, under.G):
        cen = poly.mean(axis=0)
        name = 'underbody'
        if tag[0] in (1, 2):
            for ai, s_ax in enumerate(axles):
                if abs(s_of(cen) - s_ax) < Ra + 0.03:
                    name = 'arch_liner_%s%s' % ('f' if ai == 0 else 'r', 'r' if cen[0] > 0 else 'l')
        part(name, bevel=0).add(poly, 'under_paint' if name == 'underbody' else 'rubber', SKIN)

    info = {'regions': R, 'shut_tris': counts}
    add_glass_trim(D, parts, part, sts)
    add_fittings(D, parts, part, body_tris, R, info, tips_out)
    info['arch_lip_tris'] = add_arch_lips(D, parts)
    asym = dict(ASYMMETRIC)
    asym.update(kit.get('asymmetric', {}))
    parts = symmetrize(parts, asym)
    info['asymmetric'] = {n: why for n, why in asym.items() if n in parts}
    return list(parts.values()), info


# --------------------------------------------------------------------------
# Symmetry
# --------------------------------------------------------------------------
MIRROR = np.array([-1.0, 1.0, 1.0])


def mirror_poly(p):
    """The polygon's mirror image in the centre plane, still wound outward."""
    return (np.asarray(p, float) * MIRROR)[::-1]


def twin_name(name, names):
    """door_r -> door_l, fender_fr -> fender_fl, hinge_door_r -> hinge_door_l;
    None for a part with no opposite number (bumper_r is the REAR bumper)."""
    if name and name[-1] == 'r' and (name[:-1] + 'l') in names:
        return name[:-1] + 'l'
    return None


def clip_right(poly, vals):
    """The part of a polygon at x >= 0, with its per-vertex values."""
    x = poly[:, 0].copy()
    x[np.abs(x) < 1e-7] = 0.0
    if (x >= 0).all():
        return poly, vals
    if (x <= 0).all():
        return None, None
    pts, out = [], []
    k = len(poly)
    for i in range(k):
        j = (i + 1) % k
        if x[i] >= 0:
            pts.append(poly[i])
            out.append(vals[i])
        if (x[i] > 0 > x[j]) or (x[i] < 0 < x[j]):
            t = x[i] / (x[i] - x[j])
            p = poly[i] + (poly[j] - poly[i]) * t
            p[0] = 0.0
            pts.append(p)
            out.append(vals[i] + (vals[j] - vals[i]) * t)
    if len(pts) < 3 or np.linalg.norm(poly_normal(np.array(pts))) < 1e-10:
        return None, None
    return np.array(pts), np.array(out)


def symmetrize(parts, asym=None):
    """Keep the right half of everything and mark how the left is made from it.
    asym: the names that are written as they are (ASYMMETRIC plus the car's own)."""
    asym = ASYMMETRIC if asym is None else asym
    names = set(parts)
    out = {}
    for name, p in parts.items():
        if name in asym:
            out[name] = p
            continue
        if name[-1] == 'l' and (name[:-1] + 'r') in names and (name[:-1] + 'r') not in asym:
            continue                      # written as the mirror of its right-hand twin
        polys, mats, kind, shut = [], [], [], []
        for poly, m, k, s in zip(p.polys, p.mats, p.kind, p.shut):
            q, v = clip_right(poly, s)
            if q is None:
                continue
            polys.append(q)
            mats.append(m)
            kind.append(k)
            shut.append(v)
        p.polys, p.mats, p.kind, p.shut = polys, mats, kind, shut
        p.twin = twin_name(name, names - set(asym))
        p.sym = 'pair' if p.twin else 'centre'
        if len(p):
            out[name] = p
    return out


def _skin_mat(tag, D, sts):
    """For a wall or floor polygon: the fleet material of the skin it hangs from."""
    j, i = int(tag[0]), int(tag[2])
    if j < 0:
        return 'paint'
    return fcar._strip_mat(D, j, 0.5 * (sts[i] + sts[i + 1]), {})


# --------------------------------------------------------------------------
# Glass seals, A-pillars
# --------------------------------------------------------------------------
def add_glass_trim(D, parts, part, sts):
    cab = D['cabin']
    z = lambda s: fcar._s2z(D, s)
    for gname in [n for n in list(parts) if n.startswith('glass_')]:
        g = parts[gname]
        skin = [p for p, k in zip(g.polys, g.kind) if k == SKIN]
        if not skin:
            continue
        verts, loops = weld(skin)
        seal = part('seal_' + gname[len('glass_'):], parent=g.parent, bevel=0)
        for a, b, pi in boundary_edges(loops):
            A, B = verts[a], verts[b]
            N = poly_normal(skin[pi])
            N = N / np.linalg.norm(N)
            e = B - A
            el = np.linalg.norm(e)
            if el < 1e-6 or (abs(A[0]) < 1e-6 and abs(B[0]) < 1e-6):
                continue                     # the centre line of a windshield is not an edge of it
            t = np.cross(N, e / el)          # in the glass, pointing inside (the edge runs with the polygon)
            w = min(SEAL_W, 0.45 * el + 0.004)
            up = N * SEAL_LIFT
            q = [A + up, B + up, B + t * w + up, A + t * w + up]
            for p, at in zip(q, (A, B, B, A)):
                if abs(at[0]) < 1e-6:
                    p[0] = 0.0               # a corner on the centre line stays on it, to meet its mirror image
            seal.add(q, 'rubber')

    # A-pillars: on the sheet's loft the windshield and the side glass meet on
    # one bare edge; a strip of body colour over that edge is the pillar. It
    # lies on the fixed side of the glass, so the frameless door glass still
    # opens from under it.
    for sx, nm in ((1, 'r'), (-1, 'l')):
        pillar = part('pillar_a_' + nm, bevel=0)
        rows = []
        for s in [s for s in sts if cab['A'] - 1e-6 <= s <= cab['W'] + 1e-6]:
            P, _ = fcar.half_section(D, s)
            p7, p8, p9 = (np.array([sx * P[k][0], P[k][1], z(s)]) for k in (7, 8, 9))
            d7, d9 = p7 - p8, p9 - p8
            l7, l9 = np.linalg.norm(d7), np.linalg.norm(d9)
            a = p8 + (d7 / l7 * min(0.040, 0.7 * l7) if l7 > 1e-6 else 0.0)
            c = p8 + (d9 / l9 * min(0.034, 0.5 * l9) if l9 > 1e-6 else 0.0)
            rows.append((a, p8, c))
        want = np.array([sx, 0.6, 0.0])
        for i in range(len(rows) - 1):
            (a0, m0, c0), (a1, m1, c1) = rows[i], rows[i + 1]
            for q in ((a0, m0, m1), (a0, m1, a1), (m0, c0, c1), (m0, c1, m1)):
                q = np.array(q)
                n = poly_normal(q)
                ln = np.linalg.norm(n)
                if ln < 1e-10:
                    continue
                if n @ want < 0:
                    q, n = q[::-1], -n
                pillar.add(q + n / ln * 0.004, 'paint')


# --------------------------------------------------------------------------
# Lamps, grille, mirrors, handles, plates, wipers, antenna, wing, exhaust
# --------------------------------------------------------------------------
def add_fittings(D, parts, part, body_tris, R, info, tips_out):
    cab = D['cabin']
    L = D['L']
    z = lambda s: fcar._s2z(D, s)
    top = lambda s: pl(D['top'], s)

    def on_top(x, s_, lift=0.0):
        hit = laid_on(body_tris, 'top', [(x, z(s_))], lift)
        return None if hit is None else hit[0]

    kit = kit_of(D)
    lamps = {}
    ctx = types.SimpleNamespace(D=D, parts=parts, part=part, body_tris=body_tris, R=R, info=info,
                                z=z, on_top=on_top, lamps=lamps)

    # ---- the sheet's decals become parts
    for d in D.get('decals', []):
        mat, view, tag = d['mat'], d['view'], d.get('tag')
        if kit.get('decal') and kit['decal'](ctx, d):
            continue
        if mat == 'grille':
            g = part('grille', bevel=0)
            x0, y0, x1, y1 = d['rect']
            decal(g, D, body_tris, {'view': view, 'rect': d['rect'], 'cell': 0.5}, 'rubber', 0.003)
            for k in range(3):
                yc = y0 + (y1 - y0) * (k + 1) / 4
                decal(g, D, body_tris, {'view': view, 'rect': (x0 + 0.01, yc - 0.008, x1 - 0.01, yc + 0.008), 'cell': 0.5},
                      'plastic', 0.010)
        elif mat == 'turn':
            x0, y0, x1, y1 = d['rect']
            for sx, nm in ((1, 'r'), (-1, 'l')):
                r = (x0, y0, x1, y1) if sx > 0 else (-x1, y0, -x0, y1)
                decal(part('turn_' + nm, bevel=0), D, body_tris, {'view': view, 'rect': r, 'cell': 0.12}, 'glow_turn', 0.004)
        elif mat == 'tail' and 'circle' in d:
            cx, cy, r = d['circle'][:3]
            n = 8
            back = np.array([0.0, 0.0, 1.0])
            for sx, nm in ((1, 'r'), (-1, 'l')):
                lamp = part('tail_' + nm, bevel=0)
                ring = lambda k_, off: laid_on(body_tris, 'rear', [(sx * cx + k_ * r * math.cos(2 * math.pi * i / n),
                                                                   cy + k_ * r * math.sin(2 * math.pi * i / n))
                                                                  for i in range(n)], off)
                # the lit centre is most of the lamp: with a wide lens ring the car loses its tail lamps at night
                po, pi_, pg, pb = ring(1.0, 0.007), ring(0.78, 0.007), ring(0.78, 0.005), ring(1.0, 0.0)
                if po is None or pi_ is None or pg is None or pb is None:
                    continue
                for k in range(n):
                    k2 = (k + 1) % n
                    lamp.add(facing([(po[k], po[k2], pi_[k2], pi_[k])], back)[0], 'lens_red')     # the red lens ring
                    out = (po[k] + po[k2]) / 2 - np.array([sx * cx, cy, po[k][2]])
                    lamp.add(facing([(pb[k], pb[k2], po[k2], po[k])], out)[0], 'lens_red')        # its rim down to the panel
                lamp.add(facing([pg], back)[0], 'glow_tail')                                       # the lit element under it
        elif mat == 'trim' and view == 'rear':
            # kept on the flat of the tail: a strip wider than that lands on the body side as a sliver
            name = 'bumper_r_insert' if tag == 'rbumper' else 'tail_panel'
            x0, y0, x1, y1 = d['rect']
            lim = pl(D['hw'], L) - 0.02
            decal(part(name, bevel=0), D, body_tris,
                  {'view': view, 'rect': (max(x0, -lim), y0, min(x1, lim), y1), 'cell': d.get('cell', 0.34)}, 'plastic', 0.003)
        else:
            decal(part('trim_misc', bevel=0), D, body_tris, d, MATMAP.get(mat, mat), 0.004)

    # ---- the sheet's parts
    for p in D.get('parts', []):
        t = p['type']
        if kit.get('sheet_part') and kit['sheet_part'](ctx, p):
            continue
        if t == 'mirrors':
            continue                      # the game's own door mirrors, below
        if t == 'popups':
            s0, s1, x0, x1, h = p['s0'], p['s1'], p['x0'], p['x1'], p['h']
            for sx, nm in ((1, 'r'), (-1, 'l')):
                pod = part('popup_' + nm, bevel=0.008)
                xa, xb = sx * x0, sx * x1
                xc = 0.5 * (xa + xb)
                ya = 0.5 * (top(s0) + top(s1))
                m = Mesh()
                box(m, (xc, ya + h / 2 - 0.01, z(0.5 * (s0 + s1))), (abs(xb - xa), h, s1 - s0), 'paint', {'-z': 'plastic'})
                for tri, mm in zip(m.tris, m.mats):
                    pod.add(np.array(tri), mm, SKIN)
                yl, zf = ya + h * 0.45, z(s0)
                wl, hl = abs(xb - xa) * 0.5 - 0.022, h * 0.32
                lens = [np.array([xc - wl, yl - hl, zf - 0.003]), np.array([xc - wl, yl + hl, zf - 0.003]),
                        np.array([xc + wl, yl + hl, zf - 0.003]), np.array([xc + wl, yl - hl, zf - 0.003])]
                pod.add(facing([lens], (0, 0, -1))[0], 'glow_lens')
                n, rb = 8, min(hl, wl) * 0.62
                bulb = [np.array([xc + rb * math.cos(2 * math.pi * k / n), yl + rb * math.sin(2 * math.pi * k / n), zf - 0.006])
                        for k in range(n)]
                pod.add(facing([bulb], (0, 0, -1))[0], 'glow_head')
                lamps.setdefault('head', {})[nm] = [float(xc), float(yl), float(zf - 0.006)]
            continue
        name = p.get('tag') or t
        pm = fcar.CarModel(D)
        fcar.add_part(pm, p)
        if len(pm.mesh):
            pp = part(name, bevel=0.006 if name == 'spoiler' else None)
            for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
                pp.add(np.array(tri), MATMAP.get(mm, mm), SKIN)

    for nm in ('l', 'r'):
        lamp = parts.get('tail_' + nm)
        glow = [p for p, m in zip(lamp.polys, lamp.mats) if m == 'glow_tail'] if lamp is not None else []
        if glow:
            lamps.setdefault('tail', {})[nm] = [float(v) for v in np.concatenate(glow).mean(axis=0)]
    info['lamps'] = lamps

    # ---- exhaust
    em = fcar.CarModel(D)
    tips = fcar.add_exhaust(em, body_tris)
    if len(em.mesh):
        ex = part('exhaust', bevel=0)
        for tri, mm in zip(em.mesh.tris, em.mesh.mats):
            ex.add(np.array(tri), MATMAP.get(mm, mm), DETAIL)
    if tips_out is not None:
        tips_out.extend(tips)

    # ---- door mirrors, where the game has them (P1CoupeBuilder.MIRRORS): a cup
    # open toward the driver with the mirror glass at the back of it, on a stalk
    for mi in D.get('game_mirrors', []):
        pos, size = np.asarray(mi['pos'], float), np.asarray(mi['size'], float)
        nm = 'l' if pos[0] < 0 else 'r'
        mp = part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0.008)
        Bm = yaw_basis(mi['yaw'])
        hx, hy, hz = size / 2
        wall, depth = 0.008, 0.035
        ix, iy, zb = hx - wall, hy - wall, hz - depth

        def Q(pts, out, mat, kind=DETAIL):
            q = [pos + Bm @ np.array(v, float) for v in pts]
            mp.add(facing([q], Bm @ np.asarray(out, float))[0], mat, kind)
        # the shell
        Q([(-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz), (hx, -hy, -hz)], (0, 0, -1), 'paint', SKIN)
        Q([(hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz)], (1, 0, 0), 'paint', SKIN)
        Q([(-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz), (-hx, -hy, -hz)], (-1, 0, 0), 'paint', SKIN)
        Q([(-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz)], (0, 1, 0), 'paint', SKIN)
        Q([(-hx, -hy, hz), (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz)], (0, -1, 0), 'paint', SKIN)
        # the rim round the opening
        Q([(-hx, -hy, hz), (hx, -hy, hz), (ix, -iy, hz), (-ix, -iy, hz)], (0, 0, 1), 'rubber')
        Q([(-hx, hy, hz), (-ix, iy, hz), (ix, iy, hz), (hx, hy, hz)], (0, 0, 1), 'rubber')
        Q([(-hx, -hy, hz), (-ix, -iy, hz), (-ix, iy, hz), (-hx, hy, hz)], (0, 0, 1), 'rubber')
        Q([(hx, -hy, hz), (hx, hy, hz), (ix, iy, hz), (ix, -iy, hz)], (0, 0, 1), 'rubber')
        # the mirror glass at the back of the recess, and the recess walls
        Q([(-ix, -iy, zb), (ix, -iy, zb), (ix, iy, zb), (-ix, iy, zb)], (0, 0, 1), 'mirror')
        Q([(-ix, -iy, hz), (ix, -iy, hz), (ix, -iy, zb), (-ix, -iy, zb)], (0, 1, 0), 'rubber')
        Q([(-ix, iy, zb), (ix, iy, zb), (ix, iy, hz), (-ix, iy, hz)], (0, -1, 0), 'rubber')
        Q([(-ix, -iy, zb), (-ix, iy, zb), (-ix, iy, hz), (-ix, -iy, hz)], (1, 0, 0), 'rubber')
        Q([(ix, -iy, hz), (ix, iy, hz), (ix, iy, zb), (ix, -iy, zb)], (-1, 0, 0), 'rubber')
        sx = 1.0 if pos[0] > 0 else -1.0
        obox(mp, (sx * 0.90, pos[1] - 0.015, pos[2]), (0.12, 0.035, 0.05), np.eye(3), 'plastic')

    # ---- door handles: a chrome pull over a dark recess plate, on the door skin
    hs = R['door_s1'] - 0.16
    hy_ = pl(D['belt'], hs) - 0.075
    for sx, nm in ((1, 'r'), (-1, 'l')):
        view = 'right' if sx > 0 else 'left'
        hp = part('handle_' + nm, parent='hinge_door_' + nm, bevel=0)
        decal(hp, D, body_tris, {'view': view, 'rect': (hs - 0.065, hy_ - 0.022, hs + 0.065, hy_ + 0.022), 'cell': 0.2},
              'rubber', 0.002)
        c = laid_on(body_tris, view, [(z(hs), hy_)], 0.009)
        if c is not None:
            obox(hp, c[0], (0.014, 0.016, 0.105), np.eye(3), 'chrome')

    # ---- plates, proud of the grille slats and the bumper insert
    # (view, centre height, half width, half height); the coupe's are 320 x 110, a kit's 520 x 110
    plates = kit.get('plates') or {'plate_f': ('front', 0.27, 0.16, 0.055), 'plate_r': ('rear', 0.285, 0.16, 0.055)}
    for name, (view, y, hw_p, hh_p) in plates.items():
        pp = part(name, bevel=0)
        cell = 0.6 if 'plates' in kit else 0.4
        decal(pp, D, body_tris, {'view': view, 'rect': (-hw_p, y - hh_p, hw_p, y + hh_p), 'cell': cell}, 'plate', 0.017)
        # the dark recess the plate sits in
        decal(pp, D, body_tris, {'view': view, 'rect': (-hw_p - 0.01, y - hh_p - 0.01, hw_p + 0.01, y + hh_p + 0.01), 'cell': cell},
              'rubber' if 'plates' in kit else 'plastic', 0.014)

    # ---- wipers: parked along the bottom of the windshield
    sA = cab['A']
    s_w = sA + 0.075
    g0, g1 = on_top(0.3, sA + 0.05), on_top(0.3, sA + 0.30)
    up_glass = (g1 - g0) / np.linalg.norm(g1 - g0)
    n_glass = np.cross(np.array([1.0, 0, 0]), up_glass)
    if n_glass[1] < 0:
        n_glass = -n_glass
    for nm, x0, x1 in (('r', 0.06, 0.52), ('l', -0.50, -0.04)):
        wp = part('wiper_' + nm, bevel=0)
        a_, b_ = on_top(x0, s_w) + n_glass * 0.012, on_top(x1, s_w) + n_glass * 0.012
        obox(wp, (a_ + b_) / 2, (np.linalg.norm(b_ - a_), 0.012, 0.016), frame_basis(b_ - a_, n_glass), 'rubber')
        pivot = on_top(x0 + 0.02, sA - 0.012) + np.array([0.0, 0.010, 0.0])
        mid = (a_ + b_) / 2 + n_glass * 0.010
        obox(wp, (pivot + mid) / 2, (np.linalg.norm(mid - pivot), 0.008, 0.012), frame_basis(mid - pivot, n_glass), 'plastic')

    if kit.get('fittings'):
        kit['fittings'](ctx)
    if kit.get('no_antenna'):
        return

    # ---- antenna: a short mast on the left rear quarter
    an = part('antenna', bevel=0)
    s_a = kit.get('antenna_s', cab['C'] + 0.10)   # a kit may stand it elsewhere (a wagon has no rear deck)
    base = on_top(-(pl(D['hw'], s_a) - 0.16), s_a)
    tip = base + np.array([0.0, 0.27, 0.06])
    Bt = frame_basis(tip - base, (0, 0, 1))
    r0 = 0.004
    ring = [(math.cos(a), math.sin(a)) for a in (math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6)]
    b3 = [base + Bt @ np.array([0, c * r0, s_ * r0]) for c, s_ in ring]
    t3 = [tip + Bt @ np.array([0, c * r0 * 0.6, s_ * r0 * 0.6]) for c, s_ in ring]
    for k in range(3):
        k2 = (k + 1) % 3
        an.add(facing([(b3[k], b3[k2], t3[k2], t3[k])], (b3[k] + b3[k2]) / 2 - base)[0], 'rubber')
    obox(an, base + np.array([0, 0.005, 0]), (0.03, 0.012, 0.03), np.eye(3), 'plastic')


# --------------------------------------------------------------------------
# Arch lips
# --------------------------------------------------------------------------
def on_curve(D, p, js=(3, 6, 7, 8), tol=1.5e-3):
    """Which long edge of the loft (half-section point index) a car-space
    point lies on, or None. 3 = sill / arch edge, 6 = belt, 7 = shoulder, 8 = roof corner."""
    s = p[2] + D['OHf'] + D['WB'] / 2.0
    if s < -1e-6 or s > D['L'] + 1e-6:
        return None
    P, _ = fcar.half_section(D, min(max(s, 0.0), D['L']))
    for j in js:
        if abs(abs(p[0]) - P[j][0]) < tol and abs(p[1] - P[j][1]) < tol:
            return j
    return None


def add_arch_lips(D, parts):
    """The wheel arch edge of a real wing is rolled in. Give every painted
    arch edge a LIP wide return into the well (the crease bevel then rounds
    it), and pull the liner back so the two do not share a surface."""
    axles = fcar._axles(D)
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    zax = [fcar._s2z(D, s) for s in axles]
    yc = wh['r'] + wh.get('arch_lift', 0.0)

    def in_arch(p):
        s = p[2] + D['OHf'] + D['WB'] / 2.0
        return any(abs(s - sa) < Ra - 1e-4 for sa in axles) and on_curve(D, p, js=(3,), tol=3e-4) == 3 \
            and p[1] > pl(D['floor'], s) + 0.003

    n_lip = 0
    for part in parts.values():
        if part.name.startswith('arch_liner_'):
            for poly in part.polys:
                for k in range(len(poly)):
                    if on_curve(D, poly[k], js=(3,), tol=3e-4) == 3:
                        poly[k][0] -= math.copysign(LIP, poly[k][0])
            continue
        if part.name not in ('body', 'fender_fl', 'fender_fr', 'bumper_f', 'bumper_r'):
            continue
        skin = [p for p, k, m in zip(part.polys, part.kind, part.mats) if k == SKIN and m == 'paint']
        if not skin:
            continue
        verts, loops = weld(skin)
        flag = np.array([in_arch(v) for v in verts])
        for a, b, _ in boundary_edges(loops):
            if not (flag[a] and flag[b]):
                continue
            A, B = verts[a], verts[b]
            sx = 1.0 if A[0] > 0 else -1.0
            A2, B2 = A - np.array([sx * LIP, 0, 0]), B - np.array([sx * LIP, 0, 0])
            mid = (A + B) / 2
            zc = min(zax, key=lambda v: abs(v - mid[2]))
            toward_axle = np.array([0.0, yc, zc]) - np.array([0.0, mid[1], mid[2]])
            part.add(facing([(A, B, B2, A2)], toward_axle)[0], 'paint', SKIN)
            n_lip += 2
    return n_lip


# --------------------------------------------------------------------------
# Baked vertex ambient occlusion
# --------------------------------------------------------------------------
def hemisphere(n):
    """n cosine-weighted directions about +Z, the same every run."""
    i = np.arange(n) + 0.5
    r = np.sqrt(i / n)
    phi = i * 2.399963229728653
    return np.column_stack([r * np.cos(phi), r * np.sin(phi), np.sqrt(np.maximum(0.0, 1.0 - r * r))])


def bake_ao(P, N, tris, samples=32, radius=0.35, bias=0.012, ground_y=0.0):
    """Ambient occlusion at points P with normals N against the triangles and
    the ground: `samples` rays over the hemisphere, a hit at distance t darkens
    by (1 - t / radius). -> (m,) in 0..1, 1 = open sky.

    The 12 mm bias starts every ray clear of the parts that lie on the skin
    (lamp lenses, plates, seals), which would otherwise leave a dark smear
    across the big triangle under them."""
    P = np.asarray(P, float).reshape(-1, 3)
    N = np.asarray(N, float).reshape(-1, 3)
    tris = np.asarray(tris, float).reshape(-1, 3, 3)
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    cen = tris.mean(axis=1)
    rad = np.linalg.norm(tris - cen[:, None, :], axis=2).max(axis=1)
    dirs = hemisphere(samples)
    key = np.round(np.hstack([P, N * 0.01]) / 1e-4).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    val = np.ones(len(first))
    for u, src in enumerate(first):
        n = N[src]
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            continue
        n = n / ln
        o = P[src] + n * bias
        t_ = np.cross(n, (0.0, 1.0, 0.0) if abs(n[1]) < 0.9 else (1.0, 0.0, 0.0))
        t_ /= np.linalg.norm(t_)
        b_ = np.cross(n, t_)
        Dr = dirs[:, 0:1] * t_ + dirs[:, 1:2] * b_ + dirs[:, 2:3] * n
        idx = np.nonzero(np.linalg.norm(cen - o, axis=1) < radius + rad)[0]
        tmin = np.full(samples, np.inf)
        if len(idx):
            E1, E2, T0 = e1[idx], e2[idx], o - v0[idx]
            Pv = np.cross(Dr[:, None, :], E2[None, :, :])
            det = (E1[None] * Pv).sum(-1)
            ok = np.abs(det) > 1e-12
            inv_det = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
            uu = (T0[None] * Pv).sum(-1) * inv_det
            Qv = np.cross(T0, E1)
            vv = (Dr[:, None, :] * Qv[None]).sum(-1) * inv_det
            tt = (E2 * Qv).sum(-1)[None] * inv_det
            hit = ok & (uu >= 0) & (vv >= 0) & (uu + vv <= 1) & (tt > 1e-5) & (tt < radius)
            tmin = np.where(hit, tt, np.inf).min(axis=1)
        dy = Dr[:, 1]
        down = dy < -1e-6
        tg = np.where(down, (ground_y - o[1]) / np.where(down, dy, -1.0), np.inf)
        tmin = np.minimum(tmin, np.where(tg > 0, tg, np.inf))
        val[u] = 1.0 - np.clip(1.0 - tmin / radius, 0.0, 1.0).mean()
    return val[inv]
