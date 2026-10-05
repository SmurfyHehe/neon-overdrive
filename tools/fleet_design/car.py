"""Build a car's proxy mesh from its definition (see cars.py for the format).

build(defn, opts) -> CarModel with:
  mesh     triangles + material names (body, glass, lights, wheels, parts)
  body     the body-only triangles (for ray casting)
  meta     wheel positions, exhaust tips (for B4 flames), sticker slots (3D)
"""
import copy
import math
import numpy as np

from geom import Mesh, box, prism, cylinder_x, ngon, rect, pl, place_on_surface


# Strip index of each edge of the half-section, bottom to top:
#  0 keel->floor edge, 1 wheel-well inner wall, 2 well top, 3 rocker band,
#  4 lower door, 5 upper door, 6 shoulder ledge, 7 side glass,
#  8 roof/hood outer, 9 roof/hood centre
N_HALF = 11  # points P0..P10 per half-section


class CarModel:
    def __init__(self, defn):
        self.defn = defn
        self.mesh = Mesh()
        self.body = None
        self.meta = {}


def _s2z(D, s):
    return s - (D['OHf'] + D['WB'] / 2.0)


def _axles(D):
    return [D['OHf'], D['OHf'] + D['WB']]


def _in(s, r):
    return r[0] <= s <= r[1]


def _open_region(D, s):
    for o in D.get('open', []):
        if o['s0'] < s < o['s1']:
            return o
    return None


def half_section(D, s):
    """The 11 points (x, y) of the right half-section at station s."""
    wh = D['wheel']
    yf = pl(D['floor'], s)
    hw = pl(D['hw'], s)
    yw = pl(D['waist'], s)
    yb = pl(D['belt'], s)
    top = pl(D['top'], s)
    sill_in = D.get('sill_in', 0.03)
    tumble = pl(D['tumble'], s) if isinstance(D.get('tumble'), list) else D.get('tumble', 0.05)
    gb_in = D.get('gb_in', 0.035)
    ledge = D.get('ledge', 0.012)
    rocker_h = D.get('rocker_h', yf + 0.16)

    xin = min(wh['track'] / 2 - wh['w'] / 2 - 0.035, hw - 0.12)
    ya = yf
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    yc = wh['r'] + wh.get('arch_lift', 0.0)
    for s_ax in _axles(D):
        ds = s - s_ax
        if abs(ds) < Ra:
            ya = max(ya, yc + math.sqrt(Ra * Ra - ds * ds))

    y3 = ya
    y4 = max(rocker_h, y3 + 0.004)
    y5 = max(yw, y4 + 0.01)
    y6 = max(yb, y5 + 0.015)
    y7 = y6 + ledge
    top = max(top, y7 + 0.006)

    P = [None] * N_HALF
    P[0] = (0.0, yf)
    P[1] = (xin, yf)
    P[2] = (xin, ya)
    P[3] = (hw - sill_in, y3)
    P[4] = (hw - sill_in * 0.35, y4)
    P[5] = (hw, y5)
    P[6] = (hw - tumble, y6)
    P[7] = (hw - tumble - gb_in, y7)

    o = _open_region(D, s)
    cab = D['cabin']
    if o is not None:
        wall = o.get('wall', 0.05)
        P[8] = (P[7][0] - wall, y7)
        P[9] = (P[8][0], o['floor'])
        P[10] = (0.0, o['floor'])
        return P, {'open': o}

    if cab['A'] <= s <= cab['C']:
        roof_h = cab.get('roof_h') or pl(D['top'], 0.5 * (cab['W'] + cab['R']))
        t = (top - y7) / max(1e-3, roof_h - y7)
        t = max(0.0, min(1.0, t))
        rw = pl(cab['roof_w'], s) if isinstance(cab['roof_w'], list) else cab['roof_w']
        drop = cab.get('roof_drop', 0.035)
        P[8] = (P[7][0] + t * (rw - P[7][0]), y7 + t * (top - drop - y7))
    else:
        P[8] = P[7]
    P[9] = (0.5 * P[8][0], P[8][1] + 0.72 * (top - P[8][1]))
    P[10] = (0.0, top)
    return P, {}


def _strip_mat(D, j, s, info):
    cab = D['cabin']
    if j <= 2:
        return 'under'
    if j == 3:
        return 'trim' if D.get('rocker_trim') else 'paint'
    if j in (4, 5):
        return 'paint'
    if j == 6:
        return 'paint'
    if 'open' in info:
        if j == 7:
            return 'paint'
        return info['open'].get('mat', 'interior')
    if j == 7:
        if cab['A'] <= s <= cab['D']:
            for p0, p1 in cab.get('pillars', []):
                if p0 <= s <= p1:
                    return cab.get('pillar_mat', 'pillar')
            return 'glass'
        if cab['D'] < s <= cab['C']:
            return cab.get('cpillar_mat', 'paint')
        return 'paint'
    # j == 8, 9: top surfaces
    if cab['A'] <= s <= cab['W']:
        return 'glass'
    if cab['W'] < s < cab['R']:
        return 'roof'
    if cab['R'] <= s <= cab['C'] and cab.get('backlight', True):
        return 'glass'
    return 'paint'


def stations(D):
    L = D['L']
    ss = {0.0, L}
    for key in ('top', 'floor', 'hw', 'waist', 'belt'):
        for s, _ in D[key]:
            if 0 <= s <= L:
                ss.add(round(s, 4))
    if isinstance(D.get('tumble'), list):
        for s, _ in D['tumble']:
            ss.add(round(s, 4))
    cab = D['cabin']
    for k in ('A', 'W', 'R', 'C', 'D'):
        ss.add(round(cab[k], 4))
    for p0, p1 in cab.get('pillars', []):
        ss.add(round(p0, 4))
        ss.add(round(p1, 4))
    if isinstance(cab['roof_w'], list):
        for s, _ in cab['roof_w']:
            ss.add(round(s, 4))
    for o in D.get('open', []):
        for v in (o['s0'], o['s0'] + 0.012, o['s1'] - 0.012, o['s1']):
            ss.add(round(v, 4))
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    n_arch = D.get('arch_segments', 8)
    for s_ax in _axles(D):
        for k in range(n_arch + 1):
            a = math.pi * k / n_arch
            ss.add(round(s_ax - Ra * math.cos(a), 4))
        ss.add(round(s_ax - Ra - 0.02, 4))
        ss.add(round(s_ax + Ra + 0.02, 4))
    # a little extra resolution along long straight runs keeps the cabin
    # interpolation (t) honest
    for s in np.arange(0.25, L, D.get('station_step', 0.5)):
        ss.add(round(float(s), 4))
    out = sorted(v for v in ss if 0 <= v <= L)
    merged = [out[0]]
    for v in out[1:]:
        if v - merged[-1] > 0.006:
            merged.append(v)
    if merged[-1] != L:
        merged[-1] = L
    return merged


def loft(D):
    """Body loft: list of (quad corner points, material)."""
    mesh = Mesh()
    rings = []
    infos = []
    sts = stations(D)
    for s in sts:
        P, info = half_section(D, s)
        z = _s2z(D, s)
        right = [np.array([x, y, z]) for x, y in P]
        left = [np.array([-x, y, z]) for x, y in P[1:N_HALF - 1]][::-1]
        rings.append(right + left)
        infos.append(info)
    n = len(rings[0])

    def strip_of(k):
        if k <= 9:
            return k
        if k <= 18:
            return 19 - k
        return 0

    # orientation: the right waist strip must face +X
    a, b = rings[len(rings) // 2], rings[len(rings) // 2 + 1]
    nrm = np.cross(a[5] - a[4], b[5] - a[4])
    flip = nrm[0] < 0

    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        smid = 0.5 * (sts[i] + sts[i + 1])
        info = infos[i] if 'open' in infos[i] and 'open' in infos[i + 1] else {}
        if 'open' in infos[i] and 'open' in infos[i + 1]:
            info = infos[i]
        for k in range(n):
            k2 = (k + 1) % n
            mat = _strip_mat(D, strip_of(k), smid, info)
            if flip:
                mesh.quad(a[k], b[k], b[k2], a[k2], mat)
            else:
                mesh.quad(a[k], a[k2], b[k2], b[k], mat)

    # end caps: front faces -Z, rear faces +Z
    for ring, want in ((rings[0], -1.0), (rings[-1], 1.0)):
        c = sum(ring) / len(ring)
        cap = Mesh()
        for k in range(n):
            cap.tri(c, ring[k], ring[(k + 1) % n], 'paint')
        if cap.tris:
            nz = np.cross(cap.tris[0][1] - cap.tris[0][0], cap.tris[0][2] - cap.tris[0][0])[2]
            if nz * want < 0:
                cap = Mesh()
                for k in range(n):
                    cap.tri(c, ring[(k + 1) % n], ring[k], 'paint')
        mesh.extend(cap)
    return mesh, sts


# --------------------------------------------------------------------------
# Decals (lights, grilles, livery panels, sticker slots)
# --------------------------------------------------------------------------
def _shape_pts(shape):
    if 'rect' in shape:
        return rect(*shape['rect'])
    if 'circle' in shape:
        cx, cy, r = shape['circle'][:3]
        n = shape['circle'][3] if len(shape['circle']) > 3 else 12
        return ngon(cx, cy, r, n)
    if 'ellipse' in shape:
        cx, cy, rx, ry = shape['ellipse'][:4]
        n = shape['ellipse'][4] if len(shape['ellipse']) > 4 else 12
        return ngon(cx, cy, rx, n, ry=ry)
    return shape['poly']


def _tri_subdiv(a, b, c, maxlen, out):
    la = math.dist(b, c)
    lb = math.dist(c, a)
    lc = math.dist(a, b)
    if max(la, lb, lc) <= maxlen:
        out.append((a, b, c))
        return
    ab = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    bc = ((b[0] + c[0]) / 2, (b[1] + c[1]) / 2)
    ca = ((c[0] + a[0]) / 2, (c[1] + a[1]) / 2)
    _tri_subdiv(a, ab, ca, maxlen, out)
    _tri_subdiv(ab, b, bc, maxlen, out)
    _tri_subdiv(ca, bc, c, maxlen, out)
    _tri_subdiv(ab, bc, ca, maxlen, out)


def _project_tris(body_tris, view, tris2d, offset):
    """Project 2D triangles onto the body vertex by vertex, so a decal hugs
    curved panels instead of cutting through them."""
    from geom import AXES, raycast
    d = AXES[view]
    cache = {}

    def P(a, b):
        key = (round(a, 5), round(b, 5))
        if key not in cache:
            if view in ('front', 'rear'):
                o = np.array([a, b, 0.0]) - d * 20.0
            elif view in ('left', 'right'):
                o = np.array([0.0, b, a]) - d * 20.0
            else:
                o = np.array([a, 0.0, b]) - d * 20.0
            t = raycast(body_tris, o, d)
            cache[key] = None if t is None else o + d * (t - offset)
        return cache[key]
    out = []
    for a, b, c in tris2d:
        pa, pb, pc = P(*a), P(*b), P(*c)
        if pa is None or pb is None or pc is None:
            continue
        out.append((pa, pb, pc))
    return out


def add_decal(model, body_tris, d, offset=0.006):
    """Returns the placed 3D triangles (also added to the mesh unless the
    decal is only measured, e.g. a sticker slot)."""
    D = model.defn
    view = d['view']
    pts = _shape_pts(d)
    if view in ('left', 'right'):
        pts = [(_s2z(D, a), b) for a, b in pts]
    elif view == 'top':
        pts = [(a, _s2z(D, b)) for a, b in pts]
    variants = [(view, pts)]
    if d.get('mirror'):
        if view in ('front', 'rear', 'top'):
            variants.append((view, [(-a, b) for a, b in pts][::-1]))
        elif view == 'left':
            variants.append(('right', pts[::-1]))
    maxlen = d.get('cell') or 0.08
    placed = []
    for v, p in variants:
        tris2d = []
        if 'rect' in d:
            # grid: thin strips stay cheap, wide panels still hug the body
            xs = [q[0] for q in p]
            ys = [q[1] for q in p]
            x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            nx = max(1, math.ceil((x1 - x0) / maxlen))
            ny = max(1, math.ceil((y1 - y0) / maxlen))
            for i in range(nx):
                for j in range(ny):
                    a0 = x0 + (x1 - x0) * i / nx
                    a1 = x0 + (x1 - x0) * (i + 1) / nx
                    b0 = y0 + (y1 - y0) * j / ny
                    b1 = y0 + (y1 - y0) * (j + 1) / ny
                    tris2d.append(((a0, b0), (a1, b0), (a1, b1)))
                    tris2d.append(((a0, b0), (a1, b1), (a0, b1)))
        else:
            cx = sum(q[0] for q in p) / len(p)
            cy = sum(q[1] for q in p) / len(p)
            for i in range(len(p)):
                _tri_subdiv((cx, cy), tuple(p[i]), tuple(p[(i + 1) % len(p)]), maxlen, tris2d)
        tris3 = _project_tris(body_tris, v, tris2d, d.get('offset', offset))
        if d.get('add', True):
            for a, b, c in tris3:
                model.mesh.tri(a, b, c, d['mat'])
        placed.append(tris3)
    if d.get('add', True):
        model.decal_tris = getattr(model, 'decal_tris', 0) + sum(len(t) for t in placed)
    return placed


# --------------------------------------------------------------------------
# Parts (mirrors, wings, light bars...)
# --------------------------------------------------------------------------
def _section_at(D, s):
    P, _ = half_section(D, s)
    return P


def add_part(model, p):
    D = model.defn
    m = model.mesh
    t = p['type']
    z = lambda s: _s2z(D, s)

    if t == 'mirrors':
        s = p.get('s', D['cabin']['A'] + 0.14)
        P = _section_at(D, s)
        x = P[7][0] + p.get('out', 0.09)
        y = P[7][1] + p.get('up', 0.09)
        for sx in (1, -1):
            box(m, (sx * x, y, z(s)), (0.1, 0.075, 0.14), p.get('mat', 'paint'), {'-z': 'trim'})
            box(m, (sx * (x - 0.06), y - 0.01, z(s) + 0.02), (0.06, 0.03, 0.06), 'trim')

    elif t == 'wing':
        # GT wing: plank (s0..s1 chord, y height of its underside), uprights, endplates
        s0, s1, y, span = p['s0'], p['s1'], p['y'], p['span']
        th = p.get('thick', 0.035)
        kick = p.get('kick', 0.03)  # trailing edge up
        plank = [(z(s0), y + th * 0.6), (z(s0) + 0.03, y + th), (z(s1), y + th + kick),
                 (z(s1), y + kick), (z(s0) + 0.02, y)]
        prism(m, plank, -span / 2, span / 2, p.get('mat', 'paint'))
        if p.get('endplates', True):
            ep = [(z(s0) - 0.02, y - 0.06), (z(s1) + 0.03, y - 0.05), (z(s1) + 0.03, y + th + kick + 0.05), (z(s0) - 0.02, y + th + 0.03)]
            for sx in (1, -1):
                prism(m, ep, sx * span / 2, sx * (span / 2 + 0.012), p.get('ep_mat', 'trim'))
        for ux in p.get('uprights', [0.45]):
            for sx in (1, -1):
                sm = 0.5 * (s0 + s1)
                base = pl(D['top'], sm) - 0.01
                box(m, (sx * ux, 0.5 * (base + y), z(sm)), (0.03, y - base, (s1 - s0) * 0.55), p.get('up_mat', 'trim'))

    elif t == 'hoop':
        # hoop wing: an arch across the deck, legs at the outer corners
        s0, s1, span = p['s0'], p['s1'], p['span']
        y_end, y_mid = p['y_end'], p['y_mid']
        th = p.get('thick', 0.04)
        n = 8
        xs = [(-span / 2) + span * k / n for k in range(n + 1)]
        for k in range(n):
            xa, xb = xs[k], xs[k + 1]
            ya = y_end + (y_mid - y_end) * (1 - (xa / (span / 2)) ** 2)
            yb = y_end + (y_mid - y_end) * (1 - (xb / (span / 2)) ** 2)
            prof_a = [(z(s0), ya), (z(s1), ya + 0.02), (z(s1), ya + 0.02 + th), (z(s0), ya + th)]
            prof_b = [(z(s0), yb), (z(s1), yb + 0.02), (z(s1), yb + 0.02 + th), (z(s0), yb + th)]
            A = [np.array([xa, q[1], q[0]]) for q in prof_a]
            B = [np.array([xb, q[1], q[0]]) for q in prof_b]
            for i in range(4):
                j = (i + 1) % 4
                m.quad(A[i], A[j], B[j], B[i], p.get('mat', 'paint'))
        for sx in (1, -1):
            sm = 0.5 * (s0 + s1)
            base = pl(D['top'], sm) - 0.02
            x = sx * (span / 2 - 0.03)
            box(m, (x, 0.5 * (base + y_end), z(sm)), (0.04, y_end - base + th, min(0.07, s1 - s0)), p.get('mat', 'paint'))

    elif t == 'lip':
        s0, s1, y, span = p['s0'], p['s1'], p['y'], p['span']
        prism(m, [(z(s0), y), (z(s1), y + p.get('h', 0.03)), (z(s1), y)], -span / 2, span / 2, p.get('mat', 'paint'))

    elif t == 'roof_spoiler':
        s0, s1, y0, y1, span = p['s0'], p['s1'], p['y0'], p['y1'], p['span']
        th = p.get('thick', 0.03)
        prism(m, [(z(s0), y0), (z(s1), y1), (z(s1), y1 + th), (z(s0), y0 + th + 0.01)], -span / 2, span / 2, p.get('mat', 'paint'))
        if p.get('brake_light'):
            box(m, (0, y1 + th * 0.5, z(s1) + 0.004), (0.36, th * 0.6, 0.01), 'tail')

    elif t == 'lightbar':
        s, y, w = p['s'], p['y'], p.get('w', 1.2)
        d = p.get('depth', 0.28)
        h = p.get('h', 0.1)
        box(m, (0, y + 0.015, z(s)), (w * 0.9, 0.03, d * 0.7), 'trim')  # base
        segs = p.get('segments', 6)
        for k in range(segs):
            x0 = -w / 2 + w * k / segs
            mat = 'pol_r' if (x0 + w / segs / 2) < 0 else 'pol_b'
            if p.get('pattern') == 'alt':
                mat = 'pol_r' if k % 2 == 0 else 'pol_b'
            box(m, (x0 + w / segs / 2, y + 0.03 + h / 2, z(s)), (w / segs - 0.01, h, d), mat)

    elif t == 'pushbar':
        s = p.get('s', -0.10)
        zf = z(s)
        y0, y1, w = p.get('y0', 0.30), p['y1'], p.get('w', 0.8)
        for x in (-w / 2, w / 2):
            box(m, (x, 0.5 * (y0 + y1), zf), (0.06, y1 - y0, 0.06), 'trim')
        for y in (y0 + 0.08, 0.5 * (y0 + y1), y1 - 0.03):
            box(m, (0, y, zf - 0.01), (w + 0.08, 0.05, 0.05), 'trim')
        box(m, (0, y0 + 0.04, zf + 0.12), (w * 0.6, 0.05, 0.22), 'trim')

    elif t == 'spotlight':
        cab = D['cabin']
        s = cab['A'] + p.get('ds', 0.07)
        P = _section_at(D, s)
        x = -(P[7][0] + 0.07)
        y = P[7][1] + p.get('up', 0.12)
        box(m, (x, y, z(s)), (0.04, 0.16, 0.04), 'trim')
        box(m, (x - 0.02, y + 0.10, z(s) - 0.03), (0.14, 0.14, 0.19), 'chrome', {'-z': 'head_off'})

    elif t == 'antennas':
        for (x, s, h) in p['list']:
            y0 = pl(D['top'], s)
            box(m, (x, y0 + h / 2, z(s)), (0.012, h, 0.012), 'trim')
            box(m, (x, y0 + 0.01, z(s)), (0.04, 0.02, 0.04), 'trim')

    elif t == 'roof_rails':
        s0, s1, x, h = p['s0'], p['s1'], p['x'], p.get('h', 0.06)
        for sx in (1, -1):
            y0 = pl(D['top'], s0) - 0.03
            y1 = pl(D['top'], s1) - 0.03
            ym = max(y0, y1)
            box(m, (sx * x, ym + h * 0.7, z(0.5 * (s0 + s1))), (0.04, 0.03, s1 - s0), p.get('mat', 'trim'))
            for s in (s0 + 0.04, s1 - 0.04):
                yy = pl(D['top'], s) - 0.03
                box(m, (sx * x, 0.5 * (yy + ym + h * 0.7), z(s)), (0.04, ym + h * 0.7 - yy, 0.06), p.get('mat', 'trim'))
        # crossbars reach bar_over past the rails (P6's poke out past the roof
        # edge so the rack shows in the front, rear and high outlines)
        over = p.get('bar_over', 0.05)
        for s in p.get('bars', []):
            y0 = max(pl(D['top'], s0), pl(D['top'], s1)) - 0.03 + h * 0.7
            box(m, (0, y0 + 0.03, z(s)), (2 * x + 2 * over, p.get('bar_h', 0.028), 0.045), p.get('mat', 'trim'))

    elif t == 'popups':
        s0, s1, x0, x1, h = p['s0'], p['s1'], p['x0'], p['x1'], p['h']
        for sx in (1, -1):
            xa, xb = sx * x0, sx * x1
            xc = 0.5 * (xa + xb)
            ya = pl(D['top'], s0) * 0.5 + pl(D['top'], s1) * 0.5
            box(m, (xc, ya + h / 2 - 0.01, z(0.5 * (s0 + s1))), (abs(xb - xa), h, s1 - s0), 'paint', {'-z': 'trim'})
            # lens on the front face
            yl = ya + h * 0.45
            m.quad(np.array([xa, yl - h * 0.32, z(s0) - 0.004]), np.array([xb, yl - h * 0.32, z(s0) - 0.004]),
                   np.array([xb, yl + h * 0.32, z(s0) - 0.004]), np.array([xa, yl + h * 0.32, z(s0) - 0.004]), 'head')

    elif t == 'rollhoops':
        s, h, x, w = p['s'], p['h'], p['x'], p.get('w', 0.24)
        for sx in (1, -1):
            y0 = pl(D['belt'], s)
            # headrest fairing: a tapered block
            pts = [(z(s) - 0.06, y0), (z(s) + 0.30, y0), (z(s) + 0.05, h), (z(s) - 0.04, h)]
            prism(m, pts, sx * x - w / 2, sx * x + w / 2, p.get('mat', 'paint'))

    elif t == 'scoop':
        s0, s1, w, h = p['s0'], p['s1'], p['w'], p['h']
        y0 = pl(D['top'], s0) - 0.005
        y1 = pl(D['top'], s1) - 0.005
        pts = [(z(s0), y0), (z(s1), y1), (z(s1), y1 + h), (z(s1) - 0.12, y1 + h)]
        prism(m, pts, -w / 2, w / 2, p.get('mat', 'paint'))
        m.quad(np.array([-w / 2 + 0.03, y1 + 0.01, z(s1) - 0.002]), np.array([w / 2 - 0.03, y1 + 0.01, z(s1) - 0.002]),
               np.array([w / 2 - 0.03, y1 + h - 0.01, z(s1) - 0.002]), np.array([-w / 2 + 0.03, y1 + h - 0.01, z(s1) - 0.002]), 'grille')

    elif t == 'splitter':
        s0, s1, y, w = p['s0'], p['s1'], p['y'], p['w']
        box(m, (0, y, z(0.5 * (s0 + s1))), (w, 0.022, s1 - s0), p.get('mat', 'trim'))

    elif t == 'diffuser':
        L = D['L']
        y, w, d = p['y'], p['w'], p.get('d', 0.30)
        box(m, (0, y, z(L - d / 2 + 0.03)), (w, 0.02, d), 'trim')
        for k in range(p.get('fins', 4)):
            x = -w / 2 + w * (k + 1) / (p.get('fins', 4) + 1)
            box(m, (x, y + 0.06, z(L - d / 2 + 0.03)), (0.015, 0.12, d), 'trim')

    elif t == 'skirts':
        s0, s1 = p['s0'], p['s1']
        y = p.get('y', None)
        for sx in (1, -1):
            sm = 0.5 * (s0 + s1)
            P = _section_at(D, sm)
            yy = (pl(D['floor'], sm) + 0.035) if y is None else y
            box(m, (sx * (P[3][0] + 0.012), yy, z(sm)), (0.05, 0.075, s1 - s0), p.get('mat', 'paint'))

    elif t == 'flares':
        # wide-body overfenders: a proud band following each arch
        wh = D['wheel']
        Ra = wh['r'] + wh.get('arch_gap', 0.03)
        yc = wh['r'] + wh.get('arch_lift', 0.0)
        width = p.get('band', 0.09)
        proud = p.get('proud', 0.05)
        n = 10
        for s_ax in _axles(D):
            for sx in (1, -1):
                pts_in, pts_out = [], []
                for k in range(n + 1):
                    a = math.pi * k / n
                    s = s_ax - (Ra + 0.005) * math.cos(a)
                    y = yc + (Ra + 0.005) * math.sin(a)
                    so = s_ax - (Ra + width) * math.cos(a)
                    yo = yc + (Ra + width) * math.sin(a)
                    hw = pl(D['hw'], s)
                    pts_in.append(np.array([sx * (hw + proud), y, z(s)]))
                    pts_out.append(np.array([sx * (hw + 0.004), yo, z(so)]))
                for k in range(n):
                    if sx > 0:
                        m.quad(pts_in[k], pts_in[k + 1], pts_out[k + 1], pts_out[k], p.get('mat', 'paint'))
                    else:
                        m.quad(pts_in[k], pts_out[k], pts_out[k + 1], pts_in[k + 1], p.get('mat', 'paint'))
                # lip face (looking down the arch)
                for k in range(n):
                    a_in = pts_in[k].copy(); b_in = pts_in[k + 1].copy()
                    a_b = a_in.copy(); a_b[0] = sx * (abs(a_b[0]) - proud)
                    b_b = b_in.copy(); b_b[0] = sx * (abs(b_b[0]) - proud)
                    if sx > 0:
                        m.quad(a_b, b_b, b_in, a_in, p.get('lip_mat', p.get('mat', 'paint')))
                    else:
                        m.quad(a_b, a_in, b_in, b_b, p.get('lip_mat', p.get('mat', 'paint')))

    elif t == 'mudflaps':
        for s_ax in _axles(D):
            s = s_ax + D['wheel']['r'] + 0.10
            for sx in (1, -1):
                x = sx * D['wheel']['track'] / 2
                box(m, (x, 0.2, z(s)), (D['wheel']['w'] + 0.02, 0.24, 0.012), 'trim')

    elif t == 'lightpod':
        s, y, w, n = p['s'], p['y'], p.get('w', 0.9), p.get('n', 4)
        zf = z(s)
        box(m, (0, y, zf + 0.03), (w, 0.03, 0.05), 'trim')
        for k in range(n):
            x = -w / 2 + w * (k + 0.5) / n
            box(m, (x, y + 0.075, zf), (w / n - 0.04, 0.12, 0.07), 'trim', {'-z': 'head'})

    elif t == 'bedbar':
        s, h, x = p['s'], p['h'], p['x']
        for sx in (1, -1):
            box(m, (sx * x, h / 2 + pl(D['belt'], s) / 2, z(s)), (0.06, h - pl(D['belt'], s), 0.06), 'trim')
        box(m, (0, h, z(s)), (2 * x + 0.06, 0.06, 0.06), 'trim')

    elif t == 'box':
        s, (cx, cy) = p['s'], p['xy']
        box(m, (cx, cy, z(s)), p['size'], p.get('mat', 'trim'), p.get('mats'))

    elif t == 'step':
        s0, s1, y = p['s0'], p['s1'], p['y']
        sm = 0.5 * (s0 + s1)
        for sx in (1, -1):
            hw = pl(D['hw'], sm)
            box(m, (sx * (hw - 0.02), y, z(sm)), (0.12, 0.04, s1 - s0), 'trim')

    elif t == 'tow':
        L = D['L']
        box(m, (0, p.get('y', 0.45), z(L) + 0.08), (0.08, 0.08, 0.18), 'trim')

    elif t == 'grille_guard':
        pass
    else:
        raise ValueError('unknown part ' + t)


# --------------------------------------------------------------------------
# Wheels
# --------------------------------------------------------------------------
RIM_GAPS = {
    # name: (n gaps, gap angular fraction, r0, r1)
    '5spoke': (5, 0.68, 0.30, 0.88),
    '6spoke': (6, 0.62, 0.30, 0.88),
    '10spoke': (10, 0.55, 0.32, 0.88),
    'mesh': (14, 0.45, 0.40, 0.88),
    'dish': (5, 0.50, 0.30, 0.66),
    'steel': (6, 0.0, 0.0, 0.0),
    'turbofan': (12, 0.35, 0.70, 0.90),
    'mono': (7, 0.60, 0.30, 0.86),
    'split': (10, 0.40, 0.30, 0.88),
}


def add_wheels(model):
    D = model.defn
    m = model.mesh
    wh = D['wheel']
    r = wh['r']
    style = wh.get('rim', '5spoke')
    rim_ratio = wh.get('rim_ratio', 0.68)
    nside = 16
    for ai, s_ax in enumerate(_axles(D)):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        track = wh['track'] if ai == 0 else wh.get('track_rear', wh['track'])
        zc = _s2z(D, s_ax)
        for sx in (1, -1):
            xc = sx * track / 2
            cylinder_x(m, (xc, r, zc), r, tw, nside, 'tire', 'tire_side', 'under', sx)
            xo = xc + sx * tw / 2
            R = r * rim_ratio
            rim_mat = wh.get('rim_mat', 'rim')

            def disc(rad, dx, mat, n=nside, rot=0.0, cy=r, cz=zc):
                pts = []
                for k in range(n):
                    a = rot + 2 * math.pi * k / n
                    pts.append(np.array([xo + sx * dx, cy + rad * math.sin(a), cz + rad * math.cos(a)]))
                if sx < 0:
                    pts = pts[::-1]
                m.poly(pts[::-1] if sx > 0 else pts, mat)

            disc(R, 0.003, rim_mat)
            ng, frac, r0, r1 = RIM_GAPS.get(style, RIM_GAPS['5spoke'])
            if style == 'steel':
                disc(R, 0.003, 'rim_dark')
                for k in range(6):
                    a = 2 * math.pi * k / 6
                    disc(R * 0.12, 0.006, 'under', n=6, cy=r + R * 0.58 * math.sin(a), cz=zc + R * 0.58 * math.cos(a))
                disc(R * 0.30, 0.009, 'chrome', n=10)
                continue
            if style == 'dish':
                disc(R * 0.80, 0.0045, 'rim_face')
            for k in range(ng):
                a0 = 2 * math.pi * k / ng + (1 - frac) * math.pi / ng
                a1 = a0 + 2 * math.pi / ng * frac
                pts = []
                for q in range(4):
                    a = a0 + (a1 - a0) * q / 3
                    pts.append(np.array([xo + sx * 0.006, r + R * r1 * math.sin(a), zc + R * r1 * math.cos(a)]))
                for q in range(2):
                    a = a1 - (a1 - a0) * q
                    rr = R * r0 if r0 > 0 else R * 0.3
                    pts.append(np.array([xo + sx * 0.006, r + rr * math.sin(a), zc + rr * math.cos(a)]))
                if sx < 0:
                    pts = pts[::-1]
                m.poly(pts[::-1] if sx > 0 else pts, 'rim_gap')
            disc(R * 0.18, 0.009, wh.get('hub_mat', 'chrome'), n=8)
            # brake disc + caliper peeking through the spokes (reads "performance")
            if wh.get('caliper'):
                disc(R * 0.70, 0.004, 'under', n=12)


# --------------------------------------------------------------------------
# Exhaust tips
# --------------------------------------------------------------------------
def add_exhaust(model, body_tris):
    D = model.defn
    tips = []
    for t in D.get('exhaust', []):
        L = D['L']
        if t.get('dir', 'rear') == 'rear':
            hit = place_on_surface(body_tris, 'rear', [(t['x'], t['y'])], offset=0.0)
            zr = hit[0][2] if hit else _s2z(D, L)
            # the tip sticks out 5 cm behind whatever is behind it
            z0 = zr - 0.05
            z1 = zr + t.get('out', 0.05)
            n = 10
            rx = t['r']
            ry = t['r'] * t.get('squash', 1.0)
            if t.get('shape') == 'square':
                box(model.mesh, (t['x'], t['y'], 0.5 * (z0 + z1)), (2 * rx, 2 * ry, z1 - z0), 'chrome', {'+z': 'exh_hole'})
            else:
                ring0, ring1 = [], []
                for k in range(n):
                    a = 2 * math.pi * k / n
                    ring0.append(np.array([t['x'] + rx * math.cos(a), t['y'] + ry * math.sin(a), z0]))
                    ring1.append(np.array([t['x'] + rx * math.cos(a), t['y'] + ry * math.sin(a), z1]))
                for k in range(n):
                    j = (k + 1) % n
                    model.mesh.quad(ring0[k], ring0[j], ring1[j], ring1[k], 'chrome')
                model.mesh.poly(ring1, 'exh_hole')
            tips.append({'pos': [round(t['x'], 3), round(t['y'], 3), round(z1, 3)], 'dir': [0, 0, 1], 'r': t['r']})
        else:
            # side exit just ahead of the rear wheel (or behind the front)
            s = t['s']
            zc = _s2z(D, s)
            P = _section_at(D, s)
            sx = 1 if t.get('side', 'right') == 'right' else -1
            x1 = sx * (P[3][0] + t.get('out', 0.04))
            x0 = sx * (P[3][0] - 0.10)
            n = 10
            rr = t['r']
            ring0, ring1 = [], []
            for k in range(n):
                a = 2 * math.pi * k / n
                ring0.append(np.array([x0, t['y'] + rr * math.sin(a), zc + rr * math.cos(a)]))
                ring1.append(np.array([x1, t['y'] + rr * math.sin(a), zc + rr * math.cos(a)]))
            for k in range(n):
                j = (k + 1) % n
                if sx > 0:
                    model.mesh.quad(ring0[k], ring0[j], ring1[j], ring1[k], 'chrome')
                else:
                    model.mesh.quad(ring0[k], ring1[k], ring1[j], ring0[j], 'chrome')
            model.mesh.poly(ring1 if sx < 0 else ring1[::-1], 'exh_hole')
            tips.append({'pos': [round(x1, 3), round(t['y'], 3), round(zc, 3)], 'dir': [sx, 0, 0], 'r': t['r']})
    return tips


# --------------------------------------------------------------------------
# Options (mods) and build assembly
# --------------------------------------------------------------------------
def _replace_keys(keys, new):
    lo = min(s for s, _ in new)
    hi = max(s for s, _ in new)
    kept = [k for k in keys if not (lo - 1e-6 <= k[0] <= hi + 1e-6)]
    return sorted(kept + [tuple(k) for k in new])


def apply_option(D, opt):
    for op in opt.get('ops', []):
        kind = op['op']
        if kind == 'curve':
            D[op['curve']] = _replace_keys(D[op['curve']], op['keys'])
        elif kind == 'scale_curve':
            lo, hi = op['range']
            D[op['curve']] = [(s, v + (op['add'] if lo <= s <= hi else 0.0)) for s, v in D[op['curve']]]
        elif kind == 'add':
            D.setdefault('parts', []).append(copy.deepcopy(op['part']))
        elif kind == 'remove':
            D['parts'] = [p for p in D.get('parts', []) if p.get('tag') != op['tag'] and p['type'] != op.get('type')]
        elif kind == 'set':
            obj = D
            path = op['path'].split('.')
            for k in path[:-1]:
                obj = obj[k]
            obj[path[-1]] = copy.deepcopy(op['value'])
        elif kind == 'decal':
            D.setdefault('decals', []).append(copy.deepcopy(op['decal']))
        elif kind == 'remove_decals':
            D['decals'] = [d for d in D.get('decals', []) if d.get('tag') != op['tag']]
        elif kind == 'exhaust':
            D['exhaust'] = copy.deepcopy(op['tips'])
        elif kind == 'drop':
            D['drop'] = D.get('drop', 0.0) + op['value']
        elif kind == 'cabin':
            D['cabin'].update(copy.deepcopy(op['values']))
        elif kind == 'open':
            D['open'] = copy.deepcopy(op['value'])
        else:
            raise ValueError(kind)


def resolve(defn, build=None):
    """Definition with the chosen options applied (build = {slot: option})."""
    D = copy.deepcopy(defn)
    build = build or {}
    for slot, opt_id in build.items():
        if opt_id in (None, 'stock'):
            continue
        opt = D['options'][slot][opt_id]
        apply_option(D, opt)
    return D


def build(defn, build=None, stickers=False):
    D = resolve(defn, build)
    model = CarModel(D)
    body, sts = loft(D)
    model.mesh.extend(body)
    body_tris = body.array()
    model.body = body_tris
    model.stations = sts

    for i, d in enumerate(D.get('decals', [])):
        # each decal sits a hair above the previous one, so stacked decals
        # (a lamp on a dark panel) never z-fight
        add_decal(model, body_tris, d, offset=0.004 + 0.0015 * i)
    for p in D.get('parts', []):
        add_part(model, p)
    tips = add_exhaust(model, body_tris)
    slots = []
    for st in D.get('stickers', []):
        d = dict(st)
        d['mat'] = 'slot'
        d['cell'] = 0.08
        d['offset'] = 0.012
        d['add'] = bool(stickers)
        placed = add_decal(model, body_tris, d)
        slots.append({'id': st['id'], 'view': st['view'], 'mirror': st.get('mirror', False), 'note': st.get('note', ''),
                      'rect': list(st['rect']), 'tris': placed})

    # ride height: body and everything attached to it drop, wheels don't
    drop = D.get('drop', 0.0)
    wheel_mesh = Mesh()
    model_w = CarModel(D)
    model_w.mesh = wheel_mesh
    add_wheels(model_w)
    if drop:
        model.mesh.translate((0, -drop, 0))
        model.body = model.body + np.array([0, -drop, 0])
        for t in tips:
            t['pos'][1] = round(t['pos'][1] - drop, 3)
        # sticker slots ride with the body too (B1 left them at stock height,
        # 3-5.5 cm above a lowered body; found by tests/fleet_design_check.gd)
        down = np.array([0, -drop, 0])
        for sl in slots:
            sl['tris'] = [[tuple(p + down for p in t) for t in placed] for placed in sl['tris']]
    model.mesh.extend(wheel_mesh)

    wh = D['wheel']
    model.meta = {
        'wheels': {'r': wh['r'], 'track': wh['track'], 'wheelbase': D['WB'],
                   'axle_z': [round(_s2z(D, s), 3) for s in _axles(D)]},
        'exhaust_tips': tips,
        'sticker_slots': slots,
        'drop': drop,
    }
    return model
