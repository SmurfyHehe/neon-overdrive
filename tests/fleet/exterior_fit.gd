extends SceneTree

# Exterior fit (issue #663, better-exteriors note section 5): the outside parts
# of a car from parts fit each other. Reads the car's body.glb through
# CarAssembler, in car space, and fails on any of these:
#
#   overlap   no two parts cross: where a triangle of one part goes through a
#             triangle of another, the shallower side of the crossing is at
#             most PEN (2 mm); deeper is a lamp, flare, mirror or plate sunk
#             through the panel it is laid on, or two parts through each
#             other. A part tucked wholly behind another (glass edge behind a
#             pillar) does not cross it and is not a clash. The shut-line
#             structure between panels cut from the same skin (body, hood,
#             doors, trunk, fenders, bumpers: their 15 mm returns reach into
#             the dark floor under the gap by design) is the kit test's
#             (car_parts_kits gaps), and a glass meets its own seal by design.
#             A shut-line return (rubber or dark floor) of a panel or glass
#             reaching up to RETURN_DEPTH into another's return or dark floor
#             is inside the gap, how the gap is built, and is not counted
#   glass     every door glass hangs on its door's hinge, with its seal, and
#             stays inside the door's length (DOOR_TOL); every glass part has
#             a seal; every edge of a glass is under its seal (within the
#             seal's 12 mm lip + GLASS_GAP), against an opaque part (within
#             GLASS_GAP) or tucked behind one (a part straight out from it
#             within REACH): no open edge. Only the glass's own edges count:
#             the rubber return and dark floor a shut line turns in with are
#             hidden in the gap
#   swing     every hinged panel (doors with their glass, handle, mirror and
#             flare piece; hood; deck lid with the wing; fuel flap) turned
#             open in SWEEP steps to its open angle crosses no fixed part (the
#             other panels shut) by more than PEN
#   tyre      each wheel's tread and outer face (its rubber), at rest and (fronts) at full
#             lock both ways (the car's max_steering_angle), is nowhere inside
#             a body part; at rest the tyre can rise at least MIN_RISE before
#             it touches anything (it is not already rubbing) and at most
#             arch gap + FLOAT_TOL (it fills the arch, not floating)
#   floats    every small outside part has a vertex within FLOAT_GAP (3 mm) of
#             another part: no mirror, lamp, plate, handle, flare or wing
#             hanging in the air
#
# The crossing depth: each of two crossing triangles is cut to the other's
# footprint, and on the other's plane the shallower side of what is left is
# how far it pokes through; the smaller of the two (_Cross._tri_tri). It is
# tests/car/part_fit.gd's measure (engine bays, PR 687) taken where the two
# triangles overlap, so two big triangles meeting at a corner read the real
# poke-through, not the size of the triangles.
#   ground    the lowest body vertex is at least the sheet's clearance less
#             2 cm above the road
#   tail      the lit tail elements (running and brake lamps) read apart at
#             100 m: centres at least TAIL_APART apart, each at least
#             TAIL_TALL tall (car-shape rule)
#
# Also prints, per corner, how far the tyre can rise before it touches the
# body (bump clearance; the arch stop that holds the drawn tyre under it is
# issue #670's work, not this test's).
#
# One failure is one line with the car, the check, the parts and the depth in
# mm. Thresholds are the note's; do not loosen them to make a car pass: fix
# the part.
#   godot --headless --path . -s res://tests/fleet/exterior_fit.gd
# NEON_PARTS_CAR=<id> checks one car only.

## The cars this test holds to zero clashes. A car joins when its kit passes.
const CARS := ["p3_tuner"]
const PEN := 0.002
const REACH := 0.03
const CELL := 0.06
const DOOR_TOL := 0.003
const GLASS_GAP := 0.003
const SWEEP := 10.0
const MIN_RISE := 0.005
const FLOAT_TOL := 0.01
const FLOAT_GAP := 0.003
const TAIL_APART := 0.299
const TAIL_TALL := 0.08
## How deep a shut line's turned-in edge reaches into the dark floor under its gap (README, "Shut lines").
const RETURN_DEPTH := 0.015
const CUT := ["body", "hood", "trunk", "door_l", "door_r", "door_rl", "door_rr", "fender_fl", "fender_fr", "bumper_f", "bumper_r",
	"underbody"]
## Parts that sit inside the car or the wheel wells by design (running gear,
## engine bay boxes): the float check does not ask them to touch anything.
const INNER_PREFIX := ["susp_", "caliper_", "bay_", "engine", "arch_liner_", "exhaust"]
## Part pairs that cross on purpose: "a|b" (sorted) -> why. Keep it short:
## every entry is a clash this test no longer sees.
const ALLOWED := {
	"bumper_r_insert|exhaust": "the tail pipe comes out through the valance band, as through a cut-out on a real car",
	"exhaust|underbody": "the tail pipe comes out through the sloped valance under the bumper",
}

var fails := 0

func _initialize() -> void:
	var only := OS.get_environment("NEON_PARTS_CAR")
	for id: String in CARS:
		if only != "" and id != only:
			continue
		if not CarAssembler.has_car(id):
			_fail("%s: no body.glb" % id)
			continue
		_car(id)
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _fail(what: String) -> void:
	fails += 1
	print("FAIL ", what)

# ---------- geometry ----------

## One part: {t: PackedVector3Array (3 a triangle), n: per-triangle outward normal, m: per-triangle material, v: unique vertices, box: AABB}.
static func _part(id: String, pname: String) -> Dictionary:
	var t := PackedVector3Array()
	var n := PackedVector3Array()
	var tm := PackedStringArray()
	var mats := CarAssembler.part_arrays(id, pname)
	for mname in mats:
		var m: Dictionary = mats[mname]
		var vv: PackedVector3Array = m.v
		var nn: PackedVector3Array = m.n
		var ii: PackedInt32Array = m.i
		for k in range(0, ii.size(), 3):
			var a := vv[ii[k]]
			var b := vv[ii[k + 1]]
			var c := vv[ii[k + 2]]
			var fn := (b - a).cross(c - a)
			if fn.length() < 1e-12:
				continue
			fn = fn.normalized()
			# the stored vertex normals say which side is out (the winding may be either way after import)
			if fn.dot(nn[ii[k]] + nn[ii[k + 1]] + nn[ii[k + 2]]) < 0.0:
				fn = -fn
			t.append(a)
			t.append(b)
			t.append(c)
			n.append(fn)
			tm.append(mname)
	var out := _pack(t, n)
	out["m"] = tm
	return out

static func _pack(t: PackedVector3Array, n: PackedVector3Array) -> Dictionary:
	var seen := {}
	var v := PackedVector3Array()
	var box := AABB()
	for k in t.size():
		var p := t[k]
		box = AABB(p, Vector3.ZERO) if k == 0 else box.expand(p)
		var key := Vector3i(roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0))
		if not seen.has(key):
			seen[key] = true
			v.append(p)
	return {"t": t, "n": n, "v": v, "box": box}

## The part moved by a transform (a panel swung on its hinge, a wheel turned).
static func _moved(p: Dictionary, xf: Transform3D) -> Dictionary:
	var t := PackedVector3Array()
	var n := PackedVector3Array()
	for q in (p.t as PackedVector3Array):
		t.append(xf * q)
	for q in (p.n as PackedVector3Array):
		n.append(xf.basis * q)
	return _pack(t, n)

## Triangles of many parts in a grid: {cells: {Vector3i: PackedInt32Array}, t, n, owner}.
static func _grid(parts: Dictionary, names: Array) -> Dictionary:
	var t := PackedVector3Array()
	var n := PackedVector3Array()
	var owner := PackedStringArray()
	var cells := {}
	for pname: String in names:
		var p: Dictionary = parts[pname]
		var pt: PackedVector3Array = p.t
		for k in range(0, pt.size(), 3):
			var ti := t.size() / 3
			t.append(pt[k])
			t.append(pt[k + 1])
			t.append(pt[k + 2])
			n.append((p.n as PackedVector3Array)[k / 3])
			owner.append(pname)
			var box := AABB(pt[k], Vector3.ZERO).expand(pt[k + 1]).expand(pt[k + 2]).grow(REACH)
			var c0 := _cell(box.position)
			var c1 := _cell(box.end)
			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					for z in range(c0.z, c1.z + 1):
						var key := Vector3i(x, y, z)
						# a packed array is a value: append to a copy, then store it back
						var arr: PackedInt32Array = cells.get(key, PackedInt32Array())
						arr.append(ti)
						cells[key] = arr
	return {"cells": cells, "t": t, "n": n, "owner": owner}

static func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))

static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)

## Nearest surface of the grid's parts (other than `skip`) to p: {d: distance,
## s: signed distance (negative = behind the surface), owner}. d = INF when
## nothing is within REACH. Among faces at the same distance (an edge, a
## corner) the most favourable side wins.
static func _nearest(g: Dictionary, p: Vector3, skip: Dictionary) -> Dictionary:
	var key := _cell(p)
	var best := {"d": INF, "s": INF, "owner": ""}
	if not (g.cells as Dictionary).has(key):
		return best
	var t: PackedVector3Array = g.t
	for ti in (g.cells[key] as PackedInt32Array):
		var o: String = g.owner[ti]
		if skip.has(o):
			continue
		var c := _closest_on_tri(p, t[ti * 3], t[ti * 3 + 1], t[ti * 3 + 2])
		var d := p.distance_to(c)
		if d > REACH:
			continue
		var s := (p - c).dot((g.n as PackedVector3Array)[ti])
		if d < best.d - 1e-5 or (absf(d - best.d) <= 1e-5 and s > best.s):
			best = {"d": d, "s": s, "owner": o}
	return best

# ---------- one car ----------

func _car(id: String) -> void:
	var t0 := Time.get_ticks_msec()
	var before := fails
	var parts := {}
	for pname: String in CarAssembler.part_names(id):
		parts[pname] = _part(id, pname)
	var hinges := CarAssembler.hinges(id)
	var hinge_of := {}
	for h: String in hinges:
		for pname: String in hinges[h].parts:
			hinge_of[pname] = h
	var names: Array = parts.keys()
	var grid := _grid(parts, names)
	_overlap(id, parts, hinge_of)
	_glass(id, parts, hinge_of)
	_swing(id, parts, hinges, hinge_of)
	_tyres(id, parts, grid)
	_floats(id, parts, grid)
	_ground(id, parts)
	_tail(id, parts)
	print("%s: %d parts, %d hinges: %s (%.1f s)" % [id, parts.size(), hinges.size(),
		"ok" if fails == before else "%d failures" % (fails - before), (Time.get_ticks_msec() - t0) / 1000.0])

## A point as x, y and s (metres from the nose), the way the kits measure.
static func _at(p: Vector3) -> String:
	return "x %.3f y %.3f z %.3f" % [p.x, p.y, p.z]

static func _pair(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func _overlap(id: String, parts: Dictionary, hinge_of: Dictionary) -> void:
	var cross := _Cross.new(parts, parts.keys())
	var worst := {}     # "a|b" -> mm
	for a: String in parts:
		var skip := {a: true}
		if a in CUT:
			for c: String in CUT:
				skip[c] = true
		if a.begins_with("glass_"):
			skip["seal_" + a.trim_prefix("glass_")] = true
		if a.begins_with("seal_"):
			skip["glass_" + a.trim_prefix("seal_")] = true
		var t: PackedVector3Array = parts[a].t
		var tm: PackedStringArray = parts[a].m
		for k in range(0, t.size(), 3):
			var shut: bool = _shut_part(a) and tm[k / 3] in ["rubber", "under_paint"]
			var hit := cross.crossing(t[k], t[k + 1], t[k + 2], skip, shut)
			if hit.is_empty() or hit.depth <= PEN:
				continue
			var key := _pair(a, hit.part)
			if ALLOWED.has(key):
				continue
			if hit.depth > worst.get(key, [0.0])[0]:
				worst[key] = [hit.depth, (t[k] + t[k + 1] + t[k + 2]) / 3.0]
	for k: String in worst:
		_fail("%s: overlap: %s cross by %.1f mm at %s" % [id, k.replace("|", " and "), worst[k][0] * 1000.0, _at(worst[k][1])])

func _glass(id: String, parts: Dictionary, hinge_of: Dictionary) -> void:
	for g: String in parts:
		if not g.begins_with("glass_"):
			continue
		var tag := g.trim_prefix("glass_")
		var seal := "seal_" + tag
		if not parts.has(seal):
			_fail("%s: glass: %s has no %s" % [id, g, seal])
			continue
		# every edge vertex of the glass is under its seal, or tucked behind an opaque part
		var sg := _grid(parts, [seal])
		var opaque := []
		for o: String in parts:
			if not o.begins_with("glass_"):
				opaque.append(o)
		var oc := _Cross.new(parts, opaque)
		var og := _grid(parts, opaque)
		var far := 0.0
		var where := Vector3.ZERO
		for e in _edge(parts[g]):
			var v: Vector3 = e[0]
			var hit := _nearest(sg, v, {})
			if hit.d <= GLASS_GAP + 0.012:
				continue
			if _nearest(og, v, {}).d <= GLASS_GAP:
				continue        # it meets a pillar, sail or panel
			if oc.ray(v, e[1], REACH) or oc.ray(v, -(e[1] as Vector3), REACH):
				continue        # behind (or in front of) a pillar, sail or door skin
			if hit.d > far:
				far = hit.d
				where = v
		if far > 0.0:
			_fail("%s: glass: %s has an open edge at %s, %s from %s" % [id, g, where,
				"more than 30 mm" if far == INF else "%.1f mm" % (far * 1000.0), seal])
		if not tag.begins_with("door_"):
			continue
		var door := tag
		if not parts.has(door):
			_fail("%s: glass: %s has no door %s" % [id, g, door])
			continue
		for p: String in [g, seal]:
			if hinge_of.get(p, "") != hinge_of.get(door, "-") :
				_fail("%s: glass: %s is not on %s's hinge (%s, %s)" % [id, p, door, hinge_of.get(p, "none"), hinge_of.get(door, "none")])
		var gb: AABB = parts[g].box
		var db: AABB = parts[door].box
		if gb.position.z < db.position.z - DOOR_TOL or gb.end.z > db.end.z + DOOR_TOL:
			_fail("%s: glass: %s runs %.3f..%.3f, past %s's %.3f..%.3f" % [id, g, gb.position.z, gb.end.z, door, db.position.z, db.end.z])

func _swing(id: String, parts: Dictionary, hinges: Dictionary, hinge_of: Dictionary) -> void:
	for h: String in hinges:
		var info: Dictionary = hinges[h]
		var moving: Array = info.parts
		var fixed := []
		for pname: String in parts:
			if not hinge_of.has(pname) or hinge_of[pname] != h:
				fixed.append(pname)
		var cross := _Cross.new(parts, fixed)
		var worst := {}
		var steps := maxi(1, ceili(float(info.open_deg) / SWEEP))
		for k in range(1, steps + 1):
			var deg: float = float(info.open_deg) * k / steps
			var xf := Transform3D.IDENTITY.translated(-info.origin as Vector3)
			xf = Transform3D(Basis(info.axis, deg_to_rad(info.open_sign * deg)), Vector3.ZERO) * xf
			xf = xf.translated(info.origin as Vector3)
			for pname: String in moving:
				var t: PackedVector3Array = parts[pname].t
				for j in range(0, t.size(), 3):
					var hit := cross.crossing(xf * t[j], xf * t[j + 1], xf * t[j + 2], {})
					if hit.is_empty() or hit.depth <= PEN:
						continue
					var key := "%s|%s" % [pname, hit.part]
					if worst.get(key, [0.0])[0] < hit.depth:
						worst[key] = [hit.depth, deg, (t[j] + t[j + 1] + t[j + 2]) / 3.0]
		for key: String in worst:
			var bits := key.split("|")
			_fail("%s: swing: %s on %s crosses %s by %.1f mm at %.0f deg (shut at %s)" % [id, bits[0], h, bits[1], worst[key][0] * 1000.0, worst[key][1], _at(worst[key][2])])

func _tyres(id: String, parts: Dictionary, grid: Dictionary) -> void:
	var spec := CarSpec.player_spec(id)
	var lock := rad_to_deg(float(spec.get("max_steering_angle", deg_to_rad(38.0))))
	var gap_sheet := 0.03
	for corner: String in CarAssembler.wheel_corners(id):
		var hub := CarAssembler.anchor(id, "wheel_" + corner).origin
		# the tyre alone (the wheel's rubber, hub frame): the disc and caliper inboard of it are not what fills the arch
		var mats: Dictionary = CarAssembler._load(id).wheels.get(corner, {})
		var box := AABB()
		var first := true
		for mname: String in (["rubber"] if mats.has("rubber") else mats.keys()):
			for v: Vector3 in (mats[mname].v as PackedVector3Array):
				box = AABB(v, Vector3.ZERO) if first else box.expand(v)
				first = false
		var r := maxf(box.end.y, -box.position.y)
		var out_sign := -1.0 if corner.ends_with("l") else 1.0    # the left wheels are the mirror image: out is -x
		var x_in := box.end.x if out_sign < 0.0 else box.position.x
		var x_out := box.position.x if out_sign < 0.0 else box.end.x
		var angles := [0.0]
		if corner.begins_with("f"):
			angles = [0.0, lock, -lock]
		for steer: float in angles:
			var deepest := 0.0
			var what := ""
			for v in _tyre_points(r, x_in, x_out):
				var p := hub + Basis(Vector3.UP, deg_to_rad(steer)) * v
				var hit := _nearest(grid, p, {})
				if hit.d != INF and hit.s < -PEN and -hit.s > deepest:
					deepest = -hit.s
					what = hit.owner
			if deepest > 0.0:
				_fail("%s: tyre: %s at %.0f deg steer is %.1f mm into %s" % [id, corner, steer, deepest * 1000.0, what])
		# bump: how far the tyre rises (straight ahead) before it touches anything
		var rise := -1.0
		var touched := ""
		for step in range(0, 61):
			var lift := 0.0025 * step
			for v in _tyre_points(r, x_in, x_out, true):
				var hit := _nearest(grid, hub + v + Vector3(0, lift, 0), {})
				if hit.d != INF and (hit.s < 0.0 or hit.d < 0.001):
					rise = lift
					touched = hit.owner
					break
			if rise >= 0.0:
				break
		var arch := gap_sheet
		if rise < 0.0:
			print("%s: tyre %s rises more than 150 mm before it touches the body" % [id, corner])
		else:
			print("%s: tyre %s rises %.1f mm before it touches %s" % [id, corner, rise * 1000.0, touched])
			if rise < MIN_RISE:
				_fail("%s: tyre: %s already touches %s at rest (%.1f mm)" % [id, corner, touched, rise * 1000.0])
		if rise < 0.0 or rise > arch + FLOAT_TOL:
			print("  (the arch gap check reads the arch edge, below)")
		# the arch edge over the tyre: the lowest body point straight above the tread's outer face
		var top := hub.y + r
		var gap := _gap_above(grid, hub + Vector3(x_out - out_sign * 0.01, 0, 0), top)
		if gap > arch + FLOAT_TOL:
			_fail("%s: tyre: %s has %.1f mm of air over it (arch gap %.0f + %.0f mm): floating" % [id, corner, gap * 1000.0, arch * 1000.0, FLOAT_TOL * 1000.0])

## Tread and outer-face sample points, hub frame (x_out the outer face: +x on the right, -x on the left).
static func _tyre_points(r: float, x_in: float, x_out: float, top_only := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var deg_from := -180
	var deg_to := 180
	if top_only:
		deg_from = -70
		deg_to = 70
	for a in range(deg_from, deg_to, 5):
		var ang := deg_to_rad(float(a))
		var dy := cos(ang)
		var dz := sin(ang)
		for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
			out.append(Vector3(lerpf(x_in, x_out, f), r * dy, r * dz))
		out.append(Vector3(x_out, r * 0.9 * dy, r * 0.9 * dz))
	return out

## Distance from the tyre's top (height `top`) up to the first body surface over x, z of `p`.
static func _gap_above(grid: Dictionary, p: Vector3, top: float) -> float:
	var y := top
	while y < top + 0.15:
		var hit := _nearest(grid, Vector3(p.x, y, p.z), {})
		if hit.d != INF and hit.d < 0.0015:
			return y - top
		y += 0.001
	return INF

func _floats(id: String, parts: Dictionary, grid: Dictionary) -> void:
	for a: String in parts:
		if a in CUT or a.begins_with("glass_") or a.begins_with("seal_") or a.begins_with("pillar_") or a.begins_with("sail_"):
			continue
		var inner := false
		for pre: String in INNER_PREFIX:
			if a.begins_with(pre):
				inner = true
		if inner:
			continue
		var best := INF
		for v in (parts[a].v as PackedVector3Array):
			var hit := _nearest(grid, v, {a: true})
			best = minf(best, hit.d)
			if best <= FLOAT_GAP:
				break
		if best > FLOAT_GAP:
			_fail("%s: floats: %s is %s from every other part" % [id, a, "more than 30 mm" if best == INF else "%.1f mm" % (best * 1000.0)])

func _ground(id: String, parts: Dictionary) -> void:
	var low := INF
	for a: String in parts:
		if a.begins_with("susp_") or a.begins_with("caliper_") or a == "exhaust":
			continue
		low = minf(low, (parts[a].box as AABB).position.y)
	var kinds: Dictionary = NpcCarBuilder.KINDS
	var clearance: float = float(kinds[id].clearance) if kinds.has(id) else 0.12
	if low < clearance - 0.02:
		_fail("%s: ground: lowest body point %.3f m, want at least %.3f" % [id, low, clearance - 0.02])

func _tail(id: String, parts: Dictionary) -> void:
	var lamps := []
	for a: String in parts:
		var mats := CarAssembler.part_arrays(id, a)
		for m in ["glow_tail", "glow_brake"]:
			if not mats.has(m):
				continue
			var box := AABB()
			var vv: PackedVector3Array = mats[m].v
			for k in vv.size():
				box = AABB(vv[k], Vector3.ZERO) if k == 0 else box.expand(vv[k])
			lamps.append([a, box])
	for i in lamps.size():
		var bi: AABB = lamps[i][1]
		if bi.size.y < TAIL_TALL:
			_fail("%s: tail: %s is %.0f mm tall, want %.0f" % [id, lamps[i][0], bi.size.y * 1000.0, TAIL_TALL * 1000.0])
		for j in range(i + 1, lamps.size()):
			var bj: AABB = lamps[j][1]
			var d := Vector2(bi.get_center().x - bj.get_center().x, bi.get_center().y - bj.get_center().y).length()
			if d < TAIL_APART:
				_fail("%s: tail: %s and %s are %.0f mm apart, want %.0f" % [id, lamps[i][0], lamps[j][0], d * 1000.0, TAIL_APART * 1000.0])

## A part whose turned-in edges and dark floors make the shut lines: the
## panels cut from the skin and the glass in them.
static func _shut_part(pname: String) -> bool:
	return pname in CUT or pname.begins_with("glass_")

## The glass's open edges: vertices on an edge of only one triangle of the
## part that is a glass triangle (the rubber return and dark floor a shut
## line turns in with are hidden in the gap): [vertex, the glass's outward normal there].
static func _edge(p: Dictionary) -> Array:
	var t: PackedVector3Array = p.t
	var count := {}
	var key := func(v: Vector3) -> Vector3i:
		return Vector3i(roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0))
	for k in range(0, t.size(), 3):
		for e in 3:
			var a: Vector3i = key.call(t[k + e])
			var b: Vector3i = key.call(t[k + (e + 1) % 3])
			var ek := [a, b] if (a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))) else [b, a]
			count[ek] = count.get(ek, 0) + 1
	var out := []
	var seen := {}
	for k in range(0, t.size(), 3):
		for e in 3:
			var v := t[k + e]
			var a: Vector3i = key.call(v)
			var b: Vector3i = key.call(t[k + (e + 1) % 3])
			var ek := [a, b] if (a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))) else [b, a]
			if count[ek] == 1 and not seen.has(a) and (p.m as PackedStringArray)[k / 3] == "glass":
				seen[a] = true
				out.append([v, (p.n as PackedVector3Array)[k / 3]])
	return out

## Triangles of some parts in a grid, for crossings and rays (the crossing
## depth is tests/car/part_fit.gd's, PR 687).
class _Cross:
	const C := 0.1
	var pts := PackedVector3Array()
	var owner := PackedStringArray()
	var mat := PackedStringArray()
	var cells := {}

	func _init(parts: Dictionary, names: Array) -> void:
		for pname: String in names:
			var t: PackedVector3Array = parts[pname].t
			var tm: PackedStringArray = parts[pname].get("m", PackedStringArray())
			for k in range(0, t.size(), 3):
				var ti := owner.size()
				owner.append(pname)
				mat.append(tm[k / 3] if k / 3 < tm.size() else "")
				pts.append(t[k])
				pts.append(t[k + 1])
				pts.append(t[k + 2])
				var lo := _c(t[k].min(t[k + 1]).min(t[k + 2]))
				var hi := _c(t[k].max(t[k + 1]).max(t[k + 2]))
				for x in range(lo.x, hi.x + 1):
					for y in range(lo.y, hi.y + 1):
						for z in range(lo.z, hi.z + 1):
							var c := Vector3i(x, y, z)
							var list: PackedInt32Array = cells.get(c, PackedInt32Array())
							list.append(ti)   # packed arrays are values: put it back
							cells[c] = list

	static func _c(v: Vector3) -> Vector3i:
		return Vector3i(floori(v.x / C), floori(v.y / C), floori(v.z / C))

	## The deepest crossing of triangle abc with a triangle of a part not in `skip`: {depth, part, mat} or {}.
	## `shut`: the triangle is a shut-line return (rubber or dark floor of a
	## panel or glass); its reach into another's return or dark floor up to
	## RETURN_DEPTH is inside the gap, how a shut line is built, and is not counted.
	func crossing(a: Vector3, b: Vector3, c: Vector3, skip: Dictionary, shut := false) -> Dictionary:
		var lo_v := a.min(b).min(c)
		var hi_v := a.max(b).max(c)
		var lo := _c(lo_v)
		var hi := _c(hi_v)
		var best := 0.0
		var part := ""
		var hit_mat := ""
		var seen := {}
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var cc := Vector3i(x, y, z)
					if not cells.has(cc):
						continue
					for ti: int in (cells[cc] as PackedInt32Array):
						if seen.has(ti):
							continue
						seen[ti] = true
						var who := owner[ti]
						if skip.has(who):
							continue
						var p := pts[ti * 3]
						var q := pts[ti * 3 + 1]
						var r := pts[ti * 3 + 2]
						if p.max(q).max(r).x < lo_v.x or p.min(q).min(r).x > hi_v.x \
								or p.max(q).max(r).y < lo_v.y or p.min(q).min(r).y > hi_v.y \
								or p.max(q).max(r).z < lo_v.z or p.min(q).min(r).z > hi_v.z:
							continue
						var d := _tri_tri(a, b, c, p, q, r)
						if shut and mat[ti] in ["rubber", "under_paint"] and (who in CUT or who.begins_with("glass_")) and d <= RETURN_DEPTH:
							continue
						if d > best:
							best = d
							part = who
							hit_mat = mat[ti]
		return {} if part == "" else {"depth": best, "part": part, "mat": hit_mat}

	## True when a ray from o along dir hits a triangle within `reach`.
	func ray(o: Vector3, dir: Vector3, reach: float) -> bool:
		var seen := {}
		var n := ceili(reach / 0.01)
		for k in n + 1:
			var cc := _c(o + dir * (reach * k / n))
			if not cells.has(cc):
				continue
			for ti: int in (cells[cc] as PackedInt32Array):
				if seen.has(ti):
					continue
				seen[ti] = true
				var t := _ray_tri(o + dir * 0.0005, dir, pts[ti * 3], pts[ti * 3 + 1], pts[ti * 3 + 2])
				if t >= 0.0 and t <= reach:
					return true
		return false

	static func _ray_tri(o: Vector3, dir: Vector3, p: Vector3, q: Vector3, r: Vector3) -> float:
		var e1 := q - p
		var e2 := r - p
		var h := dir.cross(e2)
		var det := e1.dot(h)
		if absf(det) < 1e-12:
			return -1.0
		var f := 1.0 / det
		var s := o - p
		var u := f * s.dot(h)
		if u < 0.0 or u > 1.0:
			return -1.0
		var qq := s.cross(e1)
		var v := f * dir.dot(qq)
		if v < 0.0 or u + v > 1.0:
			return -1.0
		var t := f * e2.dot(qq)
		return t if t >= 0.0 else -1.0

	static func _seg_tri(a: Vector3, b: Vector3, p: Vector3, q: Vector3, r: Vector3) -> bool:
		var d := b - a
		var dl := d.length()
		if dl < 1e-9:
			return false
		var t := _ray_tri(a, d / dl, p, q, r)
		return t >= 0.0 and t <= dl

	## How deep two crossing triangles poke through each other, where they
	## overlap: each triangle is cut to the other's footprint (its prism along
	## its normal), and on the other's plane the shallower side of what is left
	## is how far it pokes through; the smaller of the two. 0 when they do not
	## cross. (part_fit.gd, PR 687, takes the shallower side of the whole
	## triangle: for two big triangles that meet at a corner that reads the
	## size of the triangles, not how far one pokes through the other.)
	static func _tri_tri(a: Vector3, b: Vector3, c: Vector3, p: Vector3, q: Vector3, r: Vector3) -> float:
		var n1 := (b - a).cross(c - a)
		var n2 := (q - p).cross(r - p)
		if n1.length_squared() < 1e-14 or n2.length_squared() < 1e-14:
			return 0.0
		if not (_seg_tri(a, b, p, q, r) or _seg_tri(b, c, p, q, r) or _seg_tri(c, a, p, q, r)
				or _seg_tri(p, q, a, b, c) or _seg_tri(q, r, a, b, c) or _seg_tri(r, p, a, b, c)):
			return 0.0
		return minf(_poke(a, b, c, p, q, r), _poke(p, q, r, a, b, c))

	## How far triangle abc pokes through triangle pqr inside pqr's footprint:
	## the shallower of its two sides of pqr's plane.
	static func _poke(a: Vector3, b: Vector3, c: Vector3, p: Vector3, q: Vector3, r: Vector3) -> float:
		var n := (q - p).cross(r - p).normalized()
		var poly := PackedVector3Array([a, b, c])
		var tri := [p, q, r]
		for k in 3:
			var e0: Vector3 = tri[k]
			var e1: Vector3 = tri[(k + 1) % 3]
			var e2: Vector3 = tri[(k + 2) % 3]
			var m := n.cross(e1 - e0)
			if m.dot(e2 - e0) < 0.0:
				m = -m
			poly = _clip(poly, m, m.dot(e0))
			if poly.size() < 3:
				return 0.0
		var hi := -INF
		var lo := INF
		for v in poly:
			var d := n.dot(v - p)
			hi = maxf(hi, d)
			lo = minf(lo, d)
		return minf(hi, -lo) if hi > 0.0 and lo < 0.0 else 0.0

	## The part of a convex polygon on the side n.v >= d.
	static func _clip(poly: PackedVector3Array, n: Vector3, d: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var da := n.dot(a) - d
			var db := n.dot(b) - d
			if da >= 0.0:
				out.append(a)
			if (da >= 0.0) != (db >= 0.0):
				out.append(a + (b - a) * (da / (da - db)))
		return out
