"""Neon Overdrive fleet design generator: geometry.

Turns a car definition (profile curves, see cars.py) into a low-poly proxy
mesh, so every view on the design sheet comes from ONE 3D shape. That way the
side, top, front and rear outlines can't disagree, and the 3/4 and chase-cam
views fall out for free.

This is a design tool, not the in-game model. Stage B2/D builds the game cars
in Godot from the same numbers (fleet.json).

Coordinates follow Godot: X right, Y up, Z back (forward is -Z). The origin
is on the ground, centred between the axles. Car definitions use
s = metres from the front tip (0) to the rear tip (L).
"""
import math
import numpy as np


def pl(keys, s):
    """Piecewise-linear lookup in a list of (s, value) keys, clamped."""
    k = np.asarray(keys, float)
    return float(np.interp(s, k[:, 0], k[:, 1]))


# --------------------------------------------------------------------------
# Mesh container
# --------------------------------------------------------------------------
class Mesh:
    """Triangles (n,3,3) with one material name per triangle."""

    def __init__(self):
        self.tris = []
        self.mats = []

    def tri(self, a, b, c, mat):
        a, b, c = (np.asarray(p, float) for p in (a, b, c))
        if np.linalg.norm(np.cross(b - a, c - a)) < 1e-9:
            return
        self.tris.append((a, b, c))
        self.mats.append(mat)

    def quad(self, a, b, c, d, mat):
        self.tri(a, b, c, mat)
        self.tri(a, c, d, mat)

    def poly(self, pts, mat):
        """Fan-triangulate a convex (or star-shaped from its centroid) polygon."""
        pts = [np.asarray(p, float) for p in pts]
        if len(pts) < 3:
            return
        c = sum(pts) / len(pts)
        for i in range(len(pts)):
            self.tri(c, pts[i], pts[(i + 1) % len(pts)], mat)

    def extend(self, other):
        self.tris += other.tris
        self.mats += other.mats

    def array(self):
        if not self.tris:
            return np.zeros((0, 3, 3))
        return np.array(self.tris)

    def translate(self, d):
        d = np.asarray(d, float)
        self.tris = [(a + d, b + d, c + d) for a, b, c in self.tris]
        return self

    def mirror_x(self):
        """Mirror in X, keeping winding (so normals stay outward)."""
        m = Mesh()
        for (a, b, c), mat in zip(self.tris, self.mats):
            f = np.array([-1.0, 1.0, 1.0])
            m.tri(a * f, c * f, b * f, mat)
        return m

    def __len__(self):
        return len(self.tris)


def box(m, center, size, mat, mats=None):
    """Axis-aligned box. mats can override per face: dict of +x,-x,+y,-y,+z,-z."""
    cx, cy, cz = center
    hx, hy, hz = (s / 2 for s in size)
    v = [np.array([cx + sx * hx, cy + sy * hy, cz + sz * hz])
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    # index = (sx>0)*4 + (sy>0)*2 + (sz>0)
    def V(sx, sy, sz):
        return v[(sx > 0) * 4 + (sy > 0) * 2 + (sz > 0)]
    mats = mats or {}
    faces = {
        '+x': (V(1, -1, -1), V(1, 1, -1), V(1, 1, 1), V(1, -1, 1)),
        '-x': (V(-1, -1, 1), V(-1, 1, 1), V(-1, 1, -1), V(-1, -1, -1)),
        '+y': (V(-1, 1, -1), V(-1, 1, 1), V(1, 1, 1), V(1, 1, -1)),
        '-y': (V(-1, -1, 1), V(-1, -1, -1), V(1, -1, -1), V(1, -1, 1)),
        '+z': (V(1, -1, 1), V(1, 1, 1), V(-1, 1, 1), V(-1, -1, 1)),
        '-z': (V(-1, -1, -1), V(-1, 1, -1), V(1, 1, -1), V(1, -1, -1)),
    }
    for k, (a, b, c, d) in faces.items():
        m.quad(a, b, c, d, mats.get(k, mat))


def prism(m, pts_yz, x0, x1, mat, side_mat=None):
    """Extrude a 2D polygon given in (z, y) from x0 to x1 (for wing planks,
    endplates, scoops seen from the side)."""
    pts = [np.array(p, float) for p in pts_yz]
    n = len(pts)
    a = [np.array([x0, p[1], p[0]]) for p in pts]
    b = [np.array([x1, p[1], p[0]]) for p in pts]
    for i in range(n):
        j = (i + 1) % n
        m.quad(a[i], a[j], b[j], b[i], mat)
    m.poly(a[::-1], side_mat or mat)
    m.poly(b, side_mat or mat)


def cylinder_x(m, center, radius, width, n, mat_side, mat_cap_out, mat_cap_in, outward_sign):
    """Cylinder along X (a wheel). outward_sign=+1 for right-side wheels."""
    cx, cy, cz = center
    xo = cx + outward_sign * width / 2
    xi = cx - outward_sign * width / 2
    ring_o, ring_i = [], []
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        y = cy + radius * math.sin(a)
        z = cz + radius * math.cos(a)
        ring_o.append(np.array([xo, y, z]))
        ring_i.append(np.array([xi, y, z]))
    for k in range(n):
        j = (k + 1) % n
        if outward_sign > 0:
            m.quad(ring_i[k], ring_i[j], ring_o[j], ring_o[k], mat_side)
        else:
            m.quad(ring_o[k], ring_o[j], ring_i[j], ring_i[k], mat_side)
    if outward_sign > 0:
        m.poly(ring_o[::-1], mat_cap_out)
        m.poly(ring_i, mat_cap_in)
    else:
        m.poly(ring_o, mat_cap_out)
        m.poly(ring_i[::-1], mat_cap_in)


def ngon(cx, cy, r, n, rot=0.0, ry=None):
    ry = r if ry is None else ry
    return [(cx + r * math.cos(rot + 2 * math.pi * k / n), cy + ry * math.sin(rot + 2 * math.pi * k / n)) for k in range(n)]


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# --------------------------------------------------------------------------
# Ray casting (to stick lights, grilles and sticker slots onto the body)
# --------------------------------------------------------------------------
def raycast(tris, origin, direction):
    """Nearest hit distance of one ray against (n,3,3) triangles, or None."""
    if len(tris) == 0:
        return None
    o = np.asarray(origin, float)
    d = np.asarray(direction, float)
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = np.einsum('ij,ij->i', e1, p)
    ok = np.abs(det) > 1e-12
    inv = np.zeros_like(det)
    inv[ok] = 1.0 / det[ok]
    t0 = o - v0
    u = np.einsum('ij,ij->i', t0, p) * inv
    q = np.cross(t0, e1)
    v = (q @ d) * inv
    t = np.einsum('ij,ij->i', e2, q) * inv
    hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-6)
    if not hit.any():
        return None
    return float(t[hit].min())


AXES = {
    # view: (ray direction, how 2D (a, b) maps to 3D, start offset)
    'front': np.array([0.0, 0.0, 1.0]),   # from -Z toward +Z; 2D = (x, y)
    'rear': np.array([0.0, 0.0, -1.0]),   # from +Z toward -Z; 2D = (x, y)
    'left': np.array([1.0, 0.0, 0.0]),    # from -X toward +X; 2D = (z, y)
    'right': np.array([-1.0, 0.0, 0.0]),  # from +X toward -X; 2D = (z, y)
    'top': np.array([0.0, -1.0, 0.0]),    # from +Y down;      2D = (x, z)
}


def place_on_surface(body_tris, view, pts2d, offset=0.006, far=20.0):
    """Project a 2D polygon onto the body along a view axis. Returns 3D points
    lying `offset` metres proud of the surface, or None if it misses."""
    d = AXES[view]
    out, depths = [], []
    for a, b in pts2d:
        if view in ('front', 'rear'):
            o = np.array([a, b, 0.0]) - d * far
        elif view in ('left', 'right'):
            o = np.array([0.0, b, a]) - d * far
        else:
            o = np.array([a, 0.0, b]) - d * far
        t = raycast(body_tris, o, d)
        out.append(o)
        depths.append(t)
    known = [t for t in depths if t is not None]
    if not known:
        return None
    fallback = min(known)
    pts3 = []
    for o, t in zip(out, depths):
        t = fallback if t is None else t
        pts3.append(o + d * (t - offset))
    return pts3
