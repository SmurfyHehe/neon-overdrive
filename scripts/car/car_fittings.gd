class_name CarFittings
extends RefCounted

# The small parts every vehicle carries (car-parts-every-vehicle plan
# 2026-10-10, Roy 1171-1180): visible brakes, the lamp functions, number
# plates. Two jobs:
#
# 1. Per-car brake data (BRAKES): disc or drum per axle, rim style, caliper
#    colour. CarParts reads it through parts_cfg(). Cheap old cars keep drums
#    at the back (Roy 1172), the Bug on all four; discs are the first brake
#    upgrade (brakes_for(kind, true)).
# 2. Lamp lenses and number plates for the baked sheet bodies. The bodies
#    come from data files generated outside the game, so the lenses the data
#    lacks (reverse, third brake, indicators where the sheet has none) and
#    both plates are added here, as triangles merged into the body's own
#    "glow" and "body" surfaces: no node, no draw call. Each is placed by
#    firing a ray at the design triangles, so it sits on the surface the
#    sheet actually has (a hatch's tailgate, a sedan's boot lid) and not at a
#    guessed spot.
#
# Lamp lenses carry their function in the vertex alpha of the glow surface
# (the glow shader in NpcCarBuilder reads it): 1.0 = a sheet lamp, classed by
# colour as before; TAG_BLINKER, TAG_THIRD, TAG_REVERSE for the added ones.
#
# Rules from Roy: plates front and back on every car, traffic included
# (1174); no seat belt (1176) and no roll cage on any car (1179) are simply
# never built; wipers never break (1180).

const TAG_BLINKER := 0.7
const TAG_THIRD := 0.8
const TAG_REVERSE := 0.9

## Slots declared empty on purpose: kind -> {slot: reason}. An empty slot
## with no entry here fails tests/car/required_slots.gd.
const NONE := {
	# The Bug's sheet has its right tail lamp missing (one of its four missing bits).
	"p0_beater": {"lamp_brake": "the sheet is missing one tail lamp"},
}

## Kinds whose body is assembled from parts (a glb with named parts: head_l/r,
## tail_l/r, brake_l/r, reverse_l/r, turn_*, plate lamp, flap) and so already
## models these itself. For them this class adds NO meshes: build() returns
## nothing, and the assembler sets the chassis visual's "fittings" meta from
## the parts it has, which CarSlots reads. Lamp state still goes through
## NpcCarBuilder.set_lamps / CarLamps, which a parts body maps onto its named
## lamp parts. Empty until the parts-built bodies land (coupe PR #414, Bug).
static var PARTS_BUILT: Array[String] = []

static func parts_built(kind: String) -> bool:
	return kind in PARTS_BUILT

## Brakes per car: "disc" or "drum" per axle, "none" for the traffic cars
## (decided: wheels only). rim is a CarParts.RIM_STYLES name, caliper a
## generic colour (no branded look-alikes, Roy 1171).
const BRAKES := {
	# Rear-engine beater: drums on all four; the first brake upgrade is front discs.
	"p0_beater": {"front": "drum", "rear": "drum", "rim": "steel", "caliper": Color("#4A505B")},
	"p1_coupe": {"front": "disc", "rear": "disc", "rim": "five", "caliper": Color("#B5261E")},
	"p2_hothatch": {"front": "disc", "rear": "drum", "rim": "five", "caliper": Color("#1B1D22")},
	"p3_tuner": {"front": "disc", "rear": "disc", "rim": "mesh", "caliper": Color("#FF8A1F")},
	"p4_kei": {"front": "disc", "rear": "drum", "rim": "steel", "caliper": Color("#4A505B")},
	# Muscle (and the big sedan when it lands): discs on all four, Roy 1223.
	"p5_muscle": {"front": "disc", "rear": "disc", "rim": "five", "caliper": Color("#C9CED6")},
	"p6_crossover": {"front": "disc", "rear": "disc", "rim": "dish", "caliper": Color("#4A505B")},
	# Shop wagon: small discs in front, 200 mm drums at the rear, steel wheels
	# with hubcaps (the sheet, 98373a7).
	"p7_wagon": {"front": "disc", "rear": "drum", "rim": "steel", "caliper": Color("#4A505B")},
	# Camel work pickup: 300 mm front discs, drums at the back (the sheet).
	"p17_work_pickup": {"front": "disc", "rear": "drum", "rim": "steel", "caliper": Color("#4A505B")},
	"c1_patrol": {"front": "disc", "rear": "disc", "rim": "steel", "caliper": Color("#1B1D22")},
	"c2_patrolsuv": {"front": "disc", "rear": "disc", "rim": "steel", "caliper": Color("#1B1D22")},
	"c3_interceptor": {"front": "disc", "rear": "disc", "rim": "five", "caliper": Color("#B5261E")},
}

const PLATE_COLOR := Color("#E9E6DF")
const PLATE_EDGE := Color("#8E8B84")
const PLATE_INK := Color("#15171C")
const PLATE_THICK := 0.014
## Candidate plate heights above the ground, tried in order.
const PLATE_Y := [0.50, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74]
const REVERSE_COLOR := Color("#F2F5FF")
const BLINKER_COLOR := Color("#FFA21F")

static var _cache := {}

# ---------- brakes ----------

static func has_brakes(kind: String) -> bool:
	return BRAKES.has(kind)

## {front, rear} as CarParts reads them. `discs_upgrade` is the first brake
## upgrade: every drum axle becomes a disc axle (not wired to a garage yet).
static func brakes_for(kind: String, discs_upgrade := false) -> Dictionary:
	var b: Dictionary = BRAKES.get(kind, BRAKES["p1_coupe"])
	var f := String(b.front)
	var r := String(b.rear)
	if discs_upgrade:
		f = "disc" if f == "drum" else f
		r = "disc" if r == "drum" else r
	return {"front": f, "rear": r}

## CarParts.attach() overrides for a car kind. `tyre_mm` is the car's tyre
## width from its CarSpec (0 keeps CarParts' default).
static func parts_cfg(kind: String, tyre_mm := 0.0, discs_upgrade := false) -> Dictionary:
	var b: Dictionary = BRAKES.get(kind, BRAKES["p1_coupe"])
	var br := brakes_for(kind, discs_upgrade)
	var cfg := {"rim": b.rim, "caliper_color": b.caliper, "brake_front": br.front, "brake_rear": br.rear}
	if tyre_mm > 0.0:
		cfg["tyre_w"] = tyre_mm / 1000.0
	if NpcCarBuilder.is_npc(kind):
		cfg["rim_color"] = Color(NpcCarBuilder.KINDS[kind].data.COLORS.get("rim", "#C9CED6"))
	return cfg

static func none_reason(kind: String, slot: String) -> String:
	var n: Dictionary = NONE.get(kind, {})
	return String(n.get(slot, ""))

# ---------- lamp lenses and plates ----------

## Builds (once per key) the extra triangles for one body. `tris`/`mats` are
## the design's triangles and material indices, `names` its material names,
## `glass` and `emissive` the data's GLASS and EMISSIVE lists, `colors` its
## COLORS (name -> html). Returns
## {"body": [verts, normals, colors], "glow": [...], "counts": {...}, "points": {...}}.
## Triangles are written with Godot's clockwise front faces already.
static func build(key: String, tris: PackedVector3Array, mats: PackedByteArray, names: Array,
		glass: Array, emissive: Array, colors: Dictionary) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var out := {"body": _group(), "glow": _group(), "counts": {}, "points": {}}
	if parts_built(key.get_slice("|", 0)):
		# A body assembled from parts models its own lamps, plates and flap:
		# add no meshes here (the assembler sets the "fittings" meta).
		_cache[key] = out
		return out
	var counts: Dictionary = out.counts
	for k in ["brake_lamp", "third_brake", "reverse", "blinker_front", "blinker_rear", "plate_front", "plate_rear", "fuel_flap"]:
		counts[k] = 0
	var points: Dictionary = out.points

	var half_w := 0.0
	var top := 0.0
	for p in tris:
		half_w = maxf(half_w, absf(p.x))
		top = maxf(top, p.y)
	var bad := PackedByteArray()       # material ids a lens must not sit on
	bad.resize(names.size())
	var glass_ids := PackedByteArray()
	glass_ids.resize(names.size())
	for i in names.size():
		if names[i] in glass:
			glass_ids[i] = 1
			bad[i] = 1
		elif names[i] in emissive:
			bad[i] = 1

	# What the sheet already has: lamp sides per end, and the lamp row height.
	var head_y := 0.0
	var head_n := 0
	var tail_y := 0.0
	var tail_n := 0
	var turn_seen := {}
	var tail_seen := {}
	for t in mats.size():
		var nm: String = names[mats[t]]
		var c := (tris[t * 3] + tris[t * 3 + 1] + tris[t * 3 + 2]) / 3.0
		var side := 1 if c.x >= 0.0 else -1
		match nm:
			"head":
				head_y += c.y
				head_n += 1
			"tail":
				tail_y += c.y
				tail_n += 1
				tail_seen[side] = true
			"turn":
				turn_seen["%d|%d" % [1 if c.z > 0.0 else -1, side]] = true
	counts["brake_lamp"] = tail_seen.size()
	if head_n > 0:
		head_y /= float(head_n)
	if tail_n > 0:
		tail_y /= float(tail_n)

	var tail_col := Color(colors.get("tail", "#E5262B")).srgb_to_linear()
	var rev_col := REVERSE_COLOR.srgb_to_linear()
	var blink_col := BLINKER_COLOR.srgb_to_linear()

	# Number plates, front and back, on the first upright surface near plate height.
	var plate_y := 0.0
	for end in [1, -1]:
		var hit := _first_hit(tris, mats, bad, 0.0, PLATE_Y, end, 0.5)
		if hit.is_empty():
			continue
		var slot := "plate_rear" if end == 1 else "plate_front"
		var pw := clampf(half_w * 2.0 * 0.26, 0.30, 0.52)
		_plate(out.body, hit.p, hit.n, pw, pw * 0.33, key + slot)
		counts[slot] = 1
		points[slot] = [hit.p]
		if end == 1:
			plate_y = hit.p.y

	# Reverse lamps: a pale lens either side of the plate, on the bumper.
	var y_list: Array = [plate_y + 0.02] if plate_y > 0.0 else PLATE_Y
	for s in [-1.0, 1.0]:
		var hit := _first_hit(tris, mats, bad, s * half_w * 0.50, y_list, 1, 0.5)
		if hit.is_empty():
			hit = _first_hit(tris, mats, bad, s * half_w * 0.50, PLATE_Y, 1, 0.5)
		if hit.is_empty():
			continue
		_lens(out.glow, hit.p, hit.n, 0.12, 0.05, rev_col, TAG_REVERSE)
		counts["reverse"] += 1
		points["reverse"] = points.get("reverse", []) + [hit.p]

	# Indicators where the sheet draws none: below the head and tail lamps.
	for end in [-1, 1]:
		var slot := "blinker_rear" if end == 1 else "blinker_front"
		var base_y := (tail_y if end == 1 else head_y)
		var offs: Array = [-0.10, -0.15, -0.05, 0.05, -0.20, -0.28, 0.12, -0.35]
		var ys: Array = []
		for o in offs:
			ys.append((base_y if base_y > 0.0 else 0.62) + o)
		for s in [-1, 1]:
			if turn_seen.has("%d|%d" % [end, s]):
				counts[slot] += 1      # the sheet's own turn lamp
				continue
			var hit := {}
			for xf in [0.80, 0.72, 0.64, 0.86, 0.55]:
				hit = _first_hit(tris, mats, bad, float(s) * half_w * xf, ys, end, 0.6)
				if not hit.is_empty():
					break
			if hit.is_empty():
				hit = _first_hit(tris, mats, bad, float(s) * half_w * 0.72, PLATE_Y, end, 0.45)
			if hit.is_empty():
				continue
			_lens(out.glow, hit.p, hit.n, 0.13, 0.05, blink_col, TAG_BLINKER)
			counts[slot] += 1
			points[slot] = points.get(slot, []) + [hit.p]

	# Third brake light: on the rear glass, just under its top edge.
	var third := _rear_glass_hit(tris, mats, glass_ids, top)
	if not third.is_empty():
		var p: Vector3 = third.p + Vector3(0.0, -0.035, 0.0)
		_lens(out.glow, p, third.n, 0.30, 0.035, tail_col, TAG_THIRD)
		counts["third_brake"] = 1
		points["third_brake"] = [p]
	# The windscreen's frame, for the wipers: the glass at the centre line seen
	# from the front, lowest to highest point, and its outward normal.
	var low := {}
	var high := {}
	var yy := top
	while yy > top * 0.30:
		var h := _ray_z(tris, mats, 0.0, yy, -1)
		if not h.is_empty() and glass_ids[h.mat] != 0 and h.n.z < -0.15:
			if high.is_empty():
				high = h
			low = h
		yy -= 0.02
	if not low.is_empty():
		out["screen"] = {"base": low.p, "top": high.p, "normal": low.n, "half_w": half_w}
		points["screen"] = [low.p]

	# The fuel filler: a dark recess and a cap on the right rear quarter, just
	# above the belt line. The flap (CarFuelFlap) closes over it.
	var z_rear := 0.0
	for p in tris:
		z_rear = maxf(z_rear, p.z)
	var flap_hit := {}
	for dz in [-0.95, -1.15, -0.75, -1.35, -0.55]:
		for fy in [0.72, 0.66, 0.78, 0.60, 0.86]:
			var h := _ray_x(tris, mats, float(fy), z_rear + float(dz))
			if h.is_empty() or bad[h.mat] != 0 or h.n.x < 0.6:
				continue
			flap_hit = h
			break
		if not flap_hit.is_empty():
			break
	if not flap_hit.is_empty():
		var recess := Color("#0B0E14").srgb_to_linear()
		var cap := Color("#9AA0AA").srgb_to_linear()
		var fa := _axes(flap_hit.n)
		var fu: Vector3 = fa[0] * 0.085
		var fv: Vector3 = fa[1] * 0.06
		var fc: Vector3 = flap_hit.p + flap_hit.n * 0.004
		_emit_quad(out.body, fc - fu - fv, fc + fu - fv, fc + fu + fv, fc - fu + fv, flap_hit.n, recess)
		var cu: Vector3 = fa[0] * 0.025
		var cv: Vector3 = fa[1] * 0.025
		var cc: Vector3 = flap_hit.p + flap_hit.n * 0.007
		_emit_quad(out.body, cc - cu - cv, cc + cu - cv, cc + cu + cv, cc - cu + cv, flap_hit.n, cap)
		counts["fuel_flap"] = 1
		points["fuel_flap"] = [flap_hit.p]
		out["flap"] = {"p": flap_hit.p, "n": flap_hit.n}

	# Never grow the sheet's own box: a lens on a sloped corner would stick out
	# past the design's extents (the fleet check holds length and width to the sheet).
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in tris:
		lo = lo.min(p)
		hi = hi.max(p)
	for surf in ["body", "glow"]:
		var vs: PackedVector3Array = out[surf][0]
		for i in vs.size():
			vs[i] = vs[i].clamp(lo, hi)
		out[surf][0] = vs
	counts["tris"] = (out.body[0].size() + out.glow[0].size()) / 3
	_cache[key] = out
	return out

static func _group() -> Array:
	return [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]

## First surface a ray along z meets at (x, y), over the candidate heights
## `ys`. `end` 1 fires from the rear toward the front, -1 the other way. The
## surface must face the ray by at least `min_facing` and must not be a lamp
## or glass. Returns {"p", "n", "mat"} or {}.
static func _first_hit(tris: PackedVector3Array, mats: PackedByteArray, bad: PackedByteArray,
		x: float, ys: Array, end: int, min_facing: float) -> Dictionary:
	for y in ys:
		var h := _ray_z(tris, mats, x, float(y), end)
		if h.is_empty():
			continue
		if bad[h.mat] != 0:
			continue
		if h.n.z * float(end) < min_facing:
			continue
		return h
	return {}

## The topmost point of the rear window at the car's centre line, or {}.
static func _rear_glass_hit(tris: PackedVector3Array, mats: PackedByteArray, glass_ids: PackedByteArray, top: float) -> Dictionary:
	var y := top
	while y > top * 0.45:
		var h := _ray_z(tris, mats, 0.0, y, 1)
		if not h.is_empty() and glass_ids[h.mat] != 0 and h.n.z > 0.15:
			return h
		y -= 0.03
	return {}

## Nearest surface along z at (x, y). `end` 1: the ray starts behind the car
## and travels toward -z, so the nearest is the largest z among triangles
## facing +z; -1 is the reverse. Returns {"p", "n", "mat"} or {}.
static func _ray_z(tris: PackedVector3Array, mats: PackedByteArray, x: float, y: float, end: int) -> Dictionary:
	var best_z := -INF if end == 1 else INF
	var best := {}
	for t in mats.size():
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		if x < minf(a.x, minf(b.x, c.x)) or x > maxf(a.x, maxf(b.x, c.x)):
			continue
		if y < minf(a.y, minf(b.y, c.y)) or y > maxf(a.y, maxf(b.y, c.y)):
			continue
		var n := (b - a).cross(c - a)
		if absf(n.z) < 1e-9:
			continue
		# Barycentric weights of (x, y) in the triangle's xy projection.
		var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(d) < 1e-12:
			continue
		var w0 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / d
		var w1 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / d
		var w2 := 1.0 - w0 - w1
		if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
			continue
		var z := w0 * a.z + w1 * b.z + w2 * c.z
		if end == 1:
			if n.z <= 0.0 or z <= best_z:
				continue
		else:
			if n.z >= 0.0 or z >= best_z:
				continue
		best_z = z
		best = {"p": Vector3(x, y, z), "n": n.normalized(), "mat": mats[t]}
	return best

# ---------- emitting triangles ----------

static func _emit_tri(g: Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot's front faces are clockwise: the cross product points away from the viewer.
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for p in [a, b, c]:
		g[0].append(p)
		g[1].append(n)
		g[2].append(col)

static func _emit_quad(g: Array, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, col: Color) -> void:
	_emit_tri(g, p0, p1, p2, n, col)
	_emit_tri(g, p0, p2, p3, n, col)

static func _axes(n: Vector3) -> Array:
	var u := Vector3.UP.cross(n)
	if u.length_squared() < 1e-6:
		u = Vector3.RIGHT
	u = u.normalized()
	return [u, n.cross(u).normalized()]

## A flat lamp lens at p on a surface with normal n. Its alpha tags the function.
static func _lens(g: Array, p: Vector3, n: Vector3, w: float, h: float, col: Color, tag: float) -> void:
	var ax := _axes(n)
	var u: Vector3 = ax[0] * (w * 0.5)
	var v: Vector3 = ax[1] * (h * 0.5)
	var c := p + n * 0.006
	col.a = tag
	_emit_quad(g, c - u - v, c + u - v, c + u + v, c - u + v, n, col)

## A number plate: a thin box proud of the surface with six ink blocks on its
## face (text from the car's key, so every car reads differently).
static func _plate(g: Array, p: Vector3, n: Vector3, w: float, h: float, seed_key: String) -> void:
	var ax := _axes(n)
	var u: Vector3 = ax[0] * (w * 0.5)
	var v: Vector3 = ax[1] * (h * 0.5)
	var back := p - n * 0.002
	var front := p + n * PLATE_THICK
	var face := PLATE_COLOR.srgb_to_linear()
	var edge := PLATE_EDGE.srgb_to_linear()
	var ink := PLATE_INK.srgb_to_linear()
	_emit_quad(g, front - u - v, front + u - v, front + u + v, front - u + v, n, face)
	_emit_quad(g, back + u - v, back + u + v, front + u + v, front + u - v, u.normalized(), edge)
	_emit_quad(g, back - u - v, back - u + v, front - u + v, front - u - v, -u.normalized(), edge)
	_emit_quad(g, back + u + v, back - u + v, front - u + v, front + u + v, v.normalized(), edge)
	_emit_quad(g, back + u - v, back - u - v, front - u - v, front + u - v, -v.normalized(), edge)
	var h_seed := hash(seed_key)
	var cw := w * 0.11
	for i in 6:
		var cx := (float(i) - 2.5) * w * 0.145
		var ch := h * (0.50 if ((h_seed >> i) & 1) == 0 else 0.36)
		var c: Vector3 = front + n * 0.002 + ax[0] * cx
		var cu: Vector3 = ax[0] * (cw * 0.5)
		var cv: Vector3 = ax[1] * (ch * 0.5)
		_emit_quad(g, c - cu - cv, c + cu - cv, c + cu + cv, c - cu + cv, n, ink)

## Nearest surface along x from the car's right: the largest x among
## triangles facing +x at (y, z). Returns {"p", "n", "mat"} or {}.
static func _ray_x(tris: PackedVector3Array, mats: PackedByteArray, y: float, z: float) -> Dictionary:
	var best_x := -INF
	var best := {}
	for t in mats.size():
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		if y < minf(a.y, minf(b.y, c.y)) or y > maxf(a.y, maxf(b.y, c.y)):
			continue
		if z < minf(a.z, minf(b.z, c.z)) or z > maxf(a.z, maxf(b.z, c.z)):
			continue
		var n := (b - a).cross(c - a)
		if n.x <= 0.0:
			continue
		var d := (b.z - c.z) * (a.y - c.y) + (c.y - b.y) * (a.z - c.z)
		if absf(d) < 1e-12:
			continue
		var w0 := ((b.z - c.z) * (y - c.y) + (c.y - b.y) * (z - c.z)) / d
		var w1 := ((c.z - a.z) * (y - c.y) + (a.y - c.y) * (z - c.z)) / d
		var w2 := 1.0 - w0 - w1
		if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
			continue
		var x := w0 * a.x + w1 * b.x + w2 * c.x
		if x <= best_x:
			continue
		best_x = x
		best = {"p": Vector3(x, y, z), "n": n.normalized(), "mat": mats[t]}
	return best
