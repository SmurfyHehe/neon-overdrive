extends SceneTree

# Part fit: nothing on a car from parts clashes with anything else (engine
# bays B0, issue #644; Roy: "no conflicting parts of the car at all"). Reads
# every car's body.glb through CarAssembler and fails on any of these:
#
#   lid shut    every engine bay part (`engine`, `bay_*`) has a lid or body
#               panel straight above each of its corners, at least LID_CLEAR
#               (25 mm) up: nothing touches a shut hood
#   walls       straight out to the left and right from every corner of a bay
#               part there is a panel, at least WALL_CLEAR (10 mm) away: no
#               battery in the fender
#   bay parts   two bay parts' boxes overlap by at most PART_OVERLAP (5 mm),
#               unless the pair is declared in TOUCHING
#   swing       every panel on a hinge (hood, trunk, hatch, tailgate, barn
#               doors, doors with their glass, handle and mirror, fuel flap,
#               pop-ups), swept from shut to open (every SWEEP degrees, its
#               open angle and, for hoods, HOOD_ANGLES), never pokes through a
#               part of the car more than PEN_TOL (faces that only touch are
#               allowed); once lifted it stays LID_CLEAR clear of every bay
#               part's box. Shut, a panel's turned-in edge reaching up to
#               RETURN_DEPTH into the dark floor under its gap is how a shut
#               line is built, and is not counted
#   record      the panel clashes this test found on the cars as they were on
#               2026-10-13 are in part_fit_known.json, each with its issue
#               (#673-#676) and its depth then. A clash not on the record, or
#               deeper than it says, fails; a record whose clash is gone fails
#               too, so the entry is taken off and the list only shrinks
#   self test   the wagon with its engine, battery and hood moved where they
#               would clash must fail each check
#
# Not checked yet, because the parts do not exist: the prop rod (B3) and bay
# mods fitted in turn (B4). The test says so in its last line.
#
# A failure is one line: the car, the check, the two parts and the overlap in
# millimetres, so it can be fixed without a screenshot. The bay rules have a
# Python twin for kit edits before the glb is rebuilt:
# tools/car_pipeline/fit_check.py.
#
# Thresholds are the doc's (notes/engine-bays-better-2026-10-13.md section
# 4). Do not loosen them to make a car pass: fix the part.
#
#   godot --headless --path . -s res://tests/car/part_fit.gd
# NEON_PARTS_CAR=<id> checks one car only.

const CARS := ["p0_beater", "p1_coupe", "p2_hothatch", "p4_kei", "p5_muscle", "p7_wagon", "p8_driftcoupe", "p10_truck"]
const LID_CLEAR := 0.025
const WALL_CLEAR := 0.010
const PART_OVERLAP := 0.005
## A crossing shallower than this (on its shallow side) is two faces touching.
const PEN_TOL := 0.001
## The hood angles the doc names: 52 is the hood-pop angle B1 opens to.
const HOOD_ANGLES := [15.0, 30.0, 52.0]
const SWEEP := 15.0
const CELL := 0.1
## How deep a shut panel's turned-in edge reaches into the floor under its gap (README, "Shut lines").
const RETURN_DEPTH := 0.015
## Panel clashes found when this test was written (2026-10-13), each filed as
## an issue, with the deepest crossing measured then. See _compare_known.
const KNOWN_PATH := "res://tests/car/part_fit_known.json"
## Bay part pairs that sit against each other on purpose: "a|b" (sorted) -> why.
## Bay part pairs built touching (a hose on its tank, the belt on its pulleys):
## the same list as tools/car_pipeline/bay_kit.py TOUCHING, "a|b" sorted.
const TOUCHING := {
	"bay_hoses|bay_radiator": true, "bay_hoses|bay_shroud": true, "bay_hoses|engine": true,
	"bay_belt|engine": true, "bay_airbox|engine": true,
	"bay_battery|bay_cables": true, "bay_cables|engine": true,
	"bay_radiator|bay_shroud": true,
	# the mod parts (B4) on the stock parts they are built onto (bay_kit.py MOD_TOUCHING)
	"bay_mod_ts_turbo|engine": true, "bay_mod_tb_turbo|engine": true, "bay_mod_tt_turbos|engine": true,
	"bay_mod_ts_pipe_l|bay_mod_ts_turbo": true, "bay_mod_tb_turbo|bay_mod_ts_pipe_l": true, "bay_mod_ts_pipe_l|bay_mod_tt_turbos": true,
	"bay_mod_ts_intercooler|bay_mod_ts_pipe_l": true, "bay_mod_ts_intercooler|bay_mod_ts_pipe_f": true,
	"bay_mod_ts_pipe_f|bay_mod_ts_pipe_l": true, "bay_mod_ts_pipe_f|bay_mod_ts_pipe_r": true, "bay_hoses|bay_mod_ts_pipe_f": true,
	"bay_mod_ts_pipe_r|engine": true, "bay_hoses|bay_mod_ts_pipe_r": true,
	"bay_mod_na_cone|engine": true, "bay_hoses|bay_mod_na_cone": true,
	"bay_mod_itb|engine": true,
	"bay_mod_stroker_strip|engine": true, "bay_mod_stroker_damper|engine": true, "bay_belt|bay_mod_stroker_damper": true, "bay_hoses|bay_mod_stroker_damper": true,
	"bay_mod_cai|engine": true, "bay_hoses|bay_mod_cai": true,
	"bay_mod_pulley|engine": true, "bay_belt|bay_mod_pulley": true,
	"bay_cables|bay_mod_light_battery": true,
	"bay_mod_strut_bar|bay_strut_fl": true, "bay_mod_strut_bar|bay_strut_fr": true,
	"bay_mod_tier2_cover|engine": true, "bay_mod_tier3_cover|engine": true, "bay_mod_tier4_cover|engine": true, "bay_mod_tier5_cover|engine": true,
	"bay_mod_stroker_strip|bay_mod_tier2_cover": true, "bay_mod_stroker_strip|bay_mod_tier5_cover": true,
}
## The car the checker proves itself on (_self_test): it has an engine, a
## battery, a radiator and a hood.
const SELF_TEST_CAR := "p7_wagon"

var fails := 0

func _initialize() -> void:
	var only := OS.get_environment("NEON_PARTS_CAR")
	var t0 := Time.get_ticks_msec()
	for id: String in CARS:
		if only != "" and id != only:
			continue
		if not CarAssembler.has_car(id):
			_fail("%s: no body.glb" % id)
			continue
		_car(id)
	print("part_fit: %d cars in %.1f s; bay mods checked per fitted set (B4)" % [
		CARS.size() if only == "" else 1, (Time.get_ticks_msec() - t0) / 1000.0])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _fail(what: String) -> void:
	fails += 1
	print("FAIL ", what)

# ---------- one car ----------

func _car(id: String) -> void:
	var t0 := Time.get_ticks_msec()
	var tris := {}            # part -> PackedVector3Array, 3 a triangle, car space
	var mats := {}            # part -> PackedStringArray, the material of each triangle
	for pname: String in CarAssembler.part_names(id):
		tris[pname] = _part_tris(id, pname)
		mats[pname] = _part_mats(id, pname)
	var hinges := CarAssembler.hinges(id)
	var before := fails
	var r := _check(id, tris, mats, hinges)
	for line: String in r.fails:
		_fail(line)
	_compare_known(id, r.clashes)
	print("%s: %d bay parts, %d hinges, %d panel positions, %d panel clashes on record: %s (%.1f s)" % [
		id, CarAssembler.bay_part_names(id).size(), hinges.size(), r.swept, r.clashes.size(),
		"ok" if r.fails.is_empty() and fails == before else "failures",
		(Time.get_ticks_msec() - t0) / 1000.0])

	if id == SELF_TEST_CAR:
		_self_test(id, tris, mats, hinges, r.clashes)

## Every check on one car's parts (car space): {fails: lines, clashes:
## {"lid|part|other": {mm, deg}}, swept: panel positions tried}. The bay parts
## are the ones CarAssembler.is_bay_part names.
static func _check(id: String, tris: Dictionary, mats: Dictionary, hinges: Dictionary) -> Dictionary:
	var out: Array[String] = []
	var bay := PackedStringArray()
	for pname: String in tris:
		if CarAssembler.is_bay_part(pname):
			bay.append(pname)
	bay.sort()
	var grid := _Grid.new(tris, mats)

	# lid shut and walls: rays from every corner of every bay part
	for b: String in bay:
		var own := {b: true}
		var worst_up := {}    # hit part -> clearance
		var worst_side := {}
		var bare_up := 0
		var bare_side := 0
		var verts := _unique(tris[b])
		for v: Vector3 in verts:
			var up := grid.ray(v, Vector3.UP, own, bay)
			if up.is_empty():
				bare_up += 1
			elif up.t < LID_CLEAR:
				worst_up[up.part] = minf(worst_up.get(up.part, INF), up.t)
			for dir in [Vector3.RIGHT, Vector3.LEFT]:
				var side := grid.ray(v, dir, own, bay)
				if side.is_empty():
					bare_side += 1
				elif side.t < WALL_CLEAR:
					worst_side[side.part] = minf(worst_side.get(side.part, INF), side.t)
		if bare_up > 0:
			out.append("%s: lid shut: %d corners of %s have no panel above them" % [id, bare_up, b])
		for p: String in worst_up:
			out.append("%s: lid shut: %s is %.1f mm under %s, want %.0f" % [id, b, worst_up[p] * 1000.0, p, LID_CLEAR * 1000.0])
		if bare_side > 0:
			out.append("%s: walls: %d rays from %s leave the car sideways" % [id, bare_side, b])
		for p: String in worst_side:
			out.append("%s: walls: %s is %.1f mm from %s, want %.0f" % [id, b, worst_side[p] * 1000.0, p, WALL_CLEAR * 1000.0])

	# bay part against bay part, for every set of mods the car can wear at
	# once (B4): the small and the big turbo never meet, nor a turbo and the airbox
	var seen := {}
	for keys: Array in FittedMods.combos(id, CarAssembler.bay_variants(id)):
		var active := CarAssembler.bay_active_names(id, keys)
		for i in active.size():
			for j in range(i + 1, active.size()):
				var key := "%s|%s" % [active[i], active[j]]
				if TOUCHING.has(key) or seen.has(key):
					continue
				seen[key] = true
				var over := _overlap(_box(tris[active[i]]), _box(tris[active[j]]))
				if over > PART_OVERLAP:
					out.append("%s: bay parts: %s and %s overlap %.1f mm, want at most %.0f (with %s)" % [id, active[i], active[j], over * 1000.0, PART_OVERLAP * 1000.0, str(keys) if not keys.is_empty() else "stock"])

	# panels swung on their hinges
	var bay_boxes := {}
	for b: String in bay:
		bay_boxes[b] = _box(tris[b]).grow(LID_CLEAR)
	var swept := 0
	var clashes := {}   # "hinge|part|other" -> {mm, deg}: the deepest crossing over the sweep
	for hname: String in hinges:
		var h: Dictionary = hinges[hname]
		var lid := hname.trim_prefix("hinge_")
		var moving := {}
		for p: String in h.parts:
			moving[p] = true
		for ang: float in _angles(hname, float(h.open_deg)):
			swept += 1
			var xf := _swing(h, ang)
			for p: String in h.parts:
				var src: PackedVector3Array = tris[p]
				var moved := PackedVector3Array()
				moved.resize(src.size())
				for k in src.size():
					moved[k] = xf * src[k]
				for k in range(0, moved.size(), 3):
					var hit := grid.crossing(moved[k], moved[k + 1], moved[k + 2], moving)
					if hit.is_empty() or hit.depth <= PEN_TOL:
						continue
					# Shut, a panel's turned-in edge runs into the dark floor
					# under its gap: that is how a shut line is built
					# (tools/car_pipeline/README.md, "Shut lines"), hidden.
					if ang == 0.0 and hit.mat == "under_paint" and hit.depth <= RETURN_DEPTH:
						continue
					var key := "%s|%s|%s" % [lid, p, hit.part]
					if hit.depth > float(clashes.get(key, {}).get("mm", 0.0)) / 1000.0:
						clashes[key] = {"mm": hit.depth * 1000.0, "deg": ang}
				# lifted, a panel stays clear of every bay part
				if ang > 0.0:
					for b: String in bay_boxes:
						var box: AABB = bay_boxes[b]
						var deepest := 0.0
						for v: Vector3 in moved:
							if box.has_point(v):
								deepest = maxf(deepest, _inside(box, v))
						if deepest > 0.0:
							out.append("%s: swing: %s at %.0f deg: %s comes within %.1f mm of %s, want %.0f" % [
								id, lid, ang, p, (LID_CLEAR - deepest) * 1000.0, b, LID_CLEAR * 1000.0])
	return {"fails": out, "clashes": clashes, "swept": swept}

## The checker must catch what it is for: the same car with its parts moved
## where they would clash has to fail each check, and the real car has to
## pass. A checker that finds nothing proves nothing.
func _self_test(id: String, tris: Dictionary, mats: Dictionary, hinges: Dictionary, real: Dictionary) -> void:
	var before := fails
	var cases := [
		# [what, part, move, the failure line must contain]
		["engine 10 cm up, into the shut hood", "engine", Vector3(0.0, 0.10, 0.0), "lid shut: engine is"],
		["battery 25 cm out, into the right fender", "bay_battery", Vector3(0.25, 0.0, 0.0), "rays from bay_battery leave the car"],
		["battery 20 cm over, onto the engine", "bay_battery", Vector3(-0.20, 0.0, -0.30), "bay parts: bay_battery and engine overlap"],
		["engine 20 cm up, through the hood (a blower)", "engine", Vector3(0.0, 0.20, 0.0), "swing: hood at"],
	]
	for c: Array in cases:
		var moved := tris.duplicate()
		var src: PackedVector3Array = tris[c[1]]
		var dst := PackedVector3Array()
		for v in src:
			dst.append(v + (c[2] as Vector3))
		moved[c[1]] = dst
		var r := _check(id, moved, mats, hinges)
		var caught := false
		for line: String in r.fails:
			caught = caught or line.contains(c[3])
		if not caught:
			_fail("self test: %s %s was not caught (%s)" % [id, c[0], r.fails])
	# a hood dropped 2 cm through the fenders is a new panel clash
	var dropped := tris.duplicate()
	var hood := PackedVector3Array()
	for v: Vector3 in (tris["hood"] as PackedVector3Array):
		hood.append(v + Vector3(0.0, -0.02, 0.0))
	dropped["hood"] = hood
	var r2 := _check(id, dropped, mats, hinges)
	var new_clash := false
	for key: String in r2.clashes:
		new_clash = new_clash or (key.begins_with("hood|hood|") and not real.has(key))
	_check_self(new_clash, "self test: %s hood dropped 2 cm into the fenders shows no new clash" % id)
	print("%s self test: %d planted clashes, all caught" % [id, cases.size() + 1] if fails == before else "%s self test failed" % id)

func _check_self(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)

## Every SWEEP degrees from shut, the open angle, and for a hood HOOD_ANGLES.
static func _angles(hname: String, open_deg: float) -> Array:
	var angles := [0.0]
	var a := SWEEP
	while a < open_deg:
		angles.append(a)
		a += SWEEP
	angles.append(open_deg)
	if hname == "hinge_hood":
		for ha: float in HOOD_ANGLES:
			if not angles.has(ha):
				angles.append(ha)
	angles.sort()
	return angles

## Panel clashes against the record (KNOWN): a clash not on it, or deeper
## than it says, fails; so does a record whose clash has gone (take it off,
## so the list only ever shrinks).
func _compare_known(id: String, clashes: Dictionary) -> void:
	var known: Dictionary = _known().get(id, {})
	for key: String in clashes:
		var c: Dictionary = clashes[key]
		var k := key.split("|")
		if not known.has(key):
			_fail("%s: swing: %s at %.0f deg: %s through %s by %.1f mm (a new clash)" % [id, k[0], c.deg, k[1], k[2], c.mm])
		elif c.mm > float(known[key].mm) + 0.05:
			_fail("%s: swing: %s at %.0f deg: %s through %s by %.1f mm, deeper than the %.1f on record (#%d)" % [
				id, k[0], c.deg, k[1], k[2], c.mm, float(known[key].mm), int(known[key].issue)])
	for key: String in known:
		if not clashes.has(key):
			_fail("%s: %s is fixed: take it off %s" % [id, key, KNOWN_PATH])

static var _known_cache := {}

static func _known() -> Dictionary:
	if _known_cache.is_empty():
		var f := FileAccess.open(KNOWN_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_known_cache = data.get("cars", {})
	return _known_cache

# ---------- geometry ----------

## One part's triangles, every material, car space: 3 points a triangle.
static func _part_tris(id: String, part: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mats := CarAssembler.part_arrays(id, part)
	for mname: String in mats:
		var m: Dictionary = mats[mname]
		var v: PackedVector3Array = m.v
		for k: int in (m.i as PackedInt32Array):
			out.append(v[k])
	return out

## The material of each of _part_tris's triangles, in the same order.
static func _part_mats(id: String, part: String) -> PackedStringArray:
	var out := PackedStringArray()
	var mats := CarAssembler.part_arrays(id, part)
	for mname: String in mats:
		for k in (mats[mname].i as PackedInt32Array).size() / 3:
			out.append(mname)
	return out

static func _unique(t: PackedVector3Array) -> Array:
	var seen := {}
	for v in t:
		seen[v.snappedf(0.0001)] = true
	return seen.keys()

static func _box(t: PackedVector3Array) -> AABB:
	var box := AABB(t[0], Vector3.ZERO)
	for v in t:
		box = box.expand(v)
	return box

## How far two boxes overlap: the smallest of the three overlaps, 0 if apart.
static func _overlap(a: AABB, b: AABB) -> float:
	var lo := a.position.max(b.position)
	var hi := a.end.min(b.end)
	var d := hi - lo
	return maxf(0.0, minf(d.x, minf(d.y, d.z)))

## How deep a point is inside a box: its distance to the nearest face.
static func _inside(box: AABB, v: Vector3) -> float:
	var a := v - box.position
	var b := box.end - v
	return minf(minf(minf(a.x, b.x), minf(a.y, b.y)), minf(a.z, b.z))

## The hinge turned open by `deg` (CarAssembler.build's rotation, about the
## hinge line through its origin).
static func _swing(h: Dictionary, deg: float) -> Transform3D:
	var origin: Vector3 = h.origin
	var basis := Basis(h.axis as Vector3, deg_to_rad(float(h.open_sign) * deg))
	return Transform3D(basis, origin) * Transform3D(Basis.IDENTITY, -origin)

## Every triangle of the car in a uniform grid, for rays and crossings.
class _Grid:
	var pts: PackedVector3Array = PackedVector3Array()
	var owner: PackedStringArray = PackedStringArray()   # one per triangle
	var mat: PackedStringArray = PackedStringArray()     # one per triangle
	var cells := {}                                       # Vector3i -> PackedInt32Array

	func _init(tris: Dictionary, mats: Dictionary) -> void:
		for p: String in tris:
			var t: PackedVector3Array = tris[p]
			var m: PackedStringArray = mats[p]
			for k in range(0, t.size(), 3):
				var ti := owner.size()
				owner.append(p)
				mat.append(m[k / 3])
				pts.append(t[k])
				pts.append(t[k + 1])
				pts.append(t[k + 2])
				var lo := _cell(t[k].min(t[k + 1]).min(t[k + 2]))
				var hi := _cell(t[k].max(t[k + 1]).max(t[k + 2]))
				for x in range(lo.x, hi.x + 1):
					for y in range(lo.y, hi.y + 1):
						for z in range(lo.z, hi.z + 1):
							var c := Vector3i(x, y, z)
							var list: PackedInt32Array = cells.get(c, PackedInt32Array())
							list.append(ti)   # packed arrays are values: put it back
							cells[c] = list

	static func _cell(v: Vector3) -> Vector3i:
		return Vector3i(floori(v.x / CELL), floori(v.y / CELL), floori(v.z / CELL))

	## Nearest hit along an axis ray from `o`, skipping the parts in `skip`
	## and every part in `bay`: {t, part}, or {} for none.
	func ray(o: Vector3, dir: Vector3, skip: Dictionary, bay: PackedStringArray) -> Dictionary:
		var best := INF
		var part := ""
		var c := _cell(o)
		var axis := 1 if dir.y != 0.0 else 0
		var step := 1 if dir[axis] > 0.0 else -1
		var seen := {}
		for n in 40:   # 4 m
			var cc := c
			cc[axis] += n * step
			if (n - 1) * CELL > best:
				break
			if not cells.has(cc):
				continue
			for ti: int in (cells[cc] as PackedInt32Array):
				if seen.has(ti):
					continue
				seen[ti] = true
				var who := owner[ti]
				if skip.has(who) or bay.has(who):
					continue
				var t := _ray_tri(o, dir, pts[ti * 3], pts[ti * 3 + 1], pts[ti * 3 + 2])
				if t >= 0.0 and t < best:
					best = t
					part = who
		return {} if part == "" else {"t": best, "part": part}

	## The deepest crossing of triangle abc with any triangle not of a part in
	## `skip`: {depth, part}, or {} for none.
	func crossing(a: Vector3, b: Vector3, c: Vector3, skip: Dictionary) -> Dictionary:
		var lo_v := a.min(b).min(c)
		var hi_v := a.max(b).max(c)
		var lo := _cell(lo_v)
		var hi := _cell(hi_v)
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
						if d > best:
							best = d
							part = who
							hit_mat = mat[ti]
		return {} if part == "" else {"depth": best, "part": part, "mat": hit_mat}

	## Distance along `dir` (unit) to triangle pqr, or -1.
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

	## True when segment ab passes through triangle pqr.
	static func _seg_tri(a: Vector3, b: Vector3, p: Vector3, q: Vector3, r: Vector3) -> bool:
		var d := b - a
		var dl := d.length()
		if dl < 1e-9:
			return false
		var t := _ray_tri(a, d / dl, p, q, r)
		return t >= 0.0 and t <= dl

	## How deep two crossing triangles poke through each other: on each
	## triangle's plane, the shallower side of the other triangle; the smaller
	## of the two. 0 when they do not cross.
	static func _tri_tri(a: Vector3, b: Vector3, c: Vector3, p: Vector3, q: Vector3, r: Vector3) -> float:
		var n1 := (b - a).cross(c - a)
		var n2 := (q - p).cross(r - p)
		if n1.length_squared() < 1e-14 or n2.length_squared() < 1e-14:
			return 0.0
		n1 = n1.normalized()
		n2 = n2.normalized()
		var dp := [n1.dot(p - a), n1.dot(q - a), n1.dot(r - a)]
		var d1 := minf(maxf(dp[0], maxf(dp[1], dp[2])), -minf(dp[0], minf(dp[1], dp[2])))
		if d1 <= 0.0:
			return 0.0
		var da := [n2.dot(a - p), n2.dot(b - p), n2.dot(c - p)]
		var d2 := minf(maxf(da[0], maxf(da[1], da[2])), -minf(da[0], minf(da[1], da[2])))
		if d2 <= 0.0:
			return 0.0
		if not (_seg_tri(a, b, p, q, r) or _seg_tri(b, c, p, q, r) or _seg_tri(c, a, p, q, r)
				or _seg_tri(p, q, a, b, c) or _seg_tri(q, r, a, b, c) or _seg_tri(r, p, a, b, c)):
			return 0.0
		return minf(d1, d2)
