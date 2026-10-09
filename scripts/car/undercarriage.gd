class_name Undercarriage
extends RefCounted

# The underside of a car (car-parts plan 2026-10-09, section 5b, build list
# item 3): floor pan with sills and rails, front and rear subframes with the
# control arms and anti-roll bars, the exhaust route (down-pipe, cat, mid
# pipe, muffler, tips), driveshaft and diff (RWD), transverse box and
# half-shafts (FWD), or both (AWD), and the fuel tank. Built flat-shaded with
# CockpitKit from a handful of numbers every car builder already knows, so
# every class gets it without a new mesh export.
#
# One merged mesh, one dark vertex-colour material, so it is ONE draw call per
# car. Three value steps only (pan, parts, steel): it reads as shape from the
# mirrors, on a jump and in photo mode, and it has no lights of its own.
#
# Per class (the plan's table):
#   player   the real set, always drawn
#   crew     ally and enemy cars: the real set within LOD0_END metres, a
#            dark plate (LOD1, one draw call, a dozen triangles) to LOD1_END,
#            nothing beyond; Godot's visibility ranges, no script per frame
#   cop      the same with the cop variant: push-bar brackets up front, and
#            no muffler on the interceptor (a straight pipe)
#   traffic  nothing: the sheet bodies already carry a flat dark tray in
#            their "under" faces (tools/fleet_design/car.py section strips)
#
# Space: the car's (the vehicle node's), lift included, +z is the rear and
# the ground at rest is at about -lift.y. Nothing is built below `ground_y`
# plus a safety margin, so the parts never poke through the road.

const ROLE_PLAYER := "player"
const ROLE_CREW := "crew"
const ROLE_COP := "cop"
const ROLE_TRAFFIC := "traffic"

const NODE_NAME := "Undercarriage"
const PLATE_NAME := "UndercarriagePlate"

## LOD0 (the real set) is drawn out to this distance on crew and cop cars.
const LOD0_END := 40.0
## LOD1 (the dark plate) is drawn from LOD0_END to this distance.
const LOD1_END := 80.0

## Three value steps. Pan = the sheet's "under" colour (fleet.json), parts a
## step up, steel a step up again. All opaque: this is its own material.
const COL_PAN := Color("#0B0E14")
const COL_PART := Color("#151922")
const COL_STEEL := Color("#2A2F38")

## Lowest point of any part above the ground, at rest.
const GROUND_MARGIN := 0.05

## Which class a kind id belongs to, from the fleet's id prefixes
## (docs/design/fleet/fleet.json: p = player, c = cop, n = traffic). An ally
## or enemy is a player-class body driven by someone else, so a car that is
## not the player passes its role in explicitly (TrafficCar.role).
static func role_for_kind(kind: String) -> String:
	if kind.begins_with("c"):
		return ROLE_COP
	if kind.begins_with("n"):
		return ROLE_TRAFFIC
	return ROLE_PLAYER

## The numbers a builder passes in. Everything in car space.
##   half_w, half_l   body half width and half length
##   floor_y          underside of the body floor (lowest body point + lift)
##   ground_y         the road at rest (about -lift.y)
##   wheel_r, wheel_x, axle_z   the visual wheels: radius, half track, half wheelbase
##   tips             [{pos, dir, r}] the body's exhaust tips (metas "exhaust_tips")
##   drive            "rwd", "fwd" or "awd"
##   variant          "" or "interceptor" (cop: straight pipe, no muffler)
static func params(half_w: float, half_l: float, floor_y: float, ground_y: float,
		wheel_r: float, wheel_x: float, axle_z: float, tips: Array, drive := "rwd", variant := "") -> Dictionary:
	return {"half_w": half_w, "half_l": half_l, "floor_y": floor_y, "ground_y": ground_y,
		"wheel_r": wheel_r, "wheel_x": wheel_x, "axle_z": axle_z, "tips": tips,
		"drive": drive, "variant": variant}

## Adds the underside to a chassis visual (before CarFx.attach, which moves
## every mesh present to the car's render layer). Traffic gets nothing.
static func attach(root: Node3D, p: Dictionary, role: String) -> void:
	if role == ROLE_TRAFFIC:
		return
	var mat := _material()
	var full := build_mesh(p, role)
	var mi := MeshInstance3D.new()
	mi.name = NODE_NAME
	mi.mesh = full
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if role == ROLE_PLAYER:
		return
	# Crew and cops: the real set near, the plate at a distance, nothing far.
	mi.visibility_range_end = LOD0_END
	mi.visibility_range_end_margin = 2.0
	var plate := MeshInstance3D.new()
	plate.name = PLATE_NAME
	plate.mesh = build_plate_mesh(p)
	plate.material_override = mat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.visibility_range_begin = LOD0_END
	plate.visibility_range_begin_margin = 2.0
	plate.visibility_range_end = LOD1_END
	plate.visibility_range_end_margin = 2.0
	root.add_child(plate)

## Draw calls this adds at the given distance from the camera (0 = next to it).
static func draw_calls(role: String, distance := 0.0) -> int:
	match role:
		ROLE_PLAYER:
			return 1
		ROLE_CREW, ROLE_COP:
			return 1 if distance < LOD1_END else 0
	return 0

static var _mat: StandardMaterial3D

static func _material() -> StandardMaterial3D:
	if _mat == null:
		# Dull steel and underseal: a little metal so the street lamps give
		# the pipes a line of light, matte enough not to mirror the sky.
		_mat = CockpitKit.material(0.9, 0.25, 0.12)
	return _mat

# ---------- the real set ----------

static func build_mesh(p: Dictionary, role: String) -> ArrayMesh:
	var k := build_kit(p, role)
	return k.commit()

static func triangle_count(p: Dictionary, role: String) -> int:
	return build_kit(p, role).tri_count()

static func build_kit(p: Dictionary, role: String) -> CockpitKit:
	var k := CockpitKit.new()
	var half_w: float = p.half_w
	var floor_y: float = p.floor_y
	var ground: float = p.ground_y
	var wheel_r: float = p.wheel_r
	var wheel_x: float = p.wheel_x
	var axle_z: float = p.axle_z
	# Depth available below the floor before the parts touch the road.
	var room: float = maxf(floor_y - ground - GROUND_MARGIN, 0.04)
	var d := func(f: float) -> float: return floor_y - minf(room, f)   # f metres below the floor, clamped
	var hub_y: float = ground + wheel_r
	var pan_w := 2.0 * half_w - 0.32
	var pan_z0 := -axle_z + 0.30
	var pan_z1 := axle_z - 0.25

	# Floor pan: a thin slab, with the sills along the sides and two rails.
	k.box(Vector3(pan_w, 0.02, pan_z1 - pan_z0), Vector3(0.0, floor_y - 0.01, (pan_z0 + pan_z1) * 0.5), COL_PAN)
	for side: float in [-1.0, 1.0]:
		k.box(Vector3(0.12, 0.05, pan_z1 - pan_z0), Vector3(side * (pan_w * 0.5 - 0.06), d.call(0.035), (pan_z0 + pan_z1) * 0.5), COL_PART)
		k.box(Vector3(0.06, 0.04, pan_z1 - pan_z0 - 0.2), Vector3(side * 0.42, d.call(0.03), (pan_z0 + pan_z1) * 0.5), COL_PART)
	# The transmission tunnel's underside, a shallow channel down the middle.
	k.box(Vector3(0.30, 0.03, pan_z1 - pan_z0 - 0.6), Vector3(0.0, d.call(0.025), (pan_z0 + pan_z1) * 0.5 - 0.1), COL_PART)

	# Subframes: an H of box members at each axle, the control arms out to
	# the hubs, and an anti-roll bar across.
	for end: float in [-1.0, 1.0]:
		var az: float = end * axle_z
		var frame_w := 2.0 * wheel_x - 0.50
		var fy: float = d.call(0.06)
		k.box(Vector3(frame_w, 0.05, 0.06), Vector3(0.0, fy, az - 0.28), COL_PART)
		k.box(Vector3(frame_w, 0.05, 0.06), Vector3(0.0, fy, az + 0.28), COL_PART)
		for side: float in [-1.0, 1.0]:
			k.box(Vector3(0.06, 0.05, 0.62), Vector3(side * frame_w * 0.5, fy, az), COL_PART)
			# Lower arms, a V from the frame to the hub; the hub is a short stub
			# so the arms end on something.
			var hub := Vector3(side * (wheel_x - 0.10), hub_y, az)
			_bar(k, Vector3(side * (frame_w * 0.5 - 0.02), fy, az - 0.26), hub, 0.035, COL_PART)
			_bar(k, Vector3(side * (frame_w * 0.5 - 0.02), fy, az + 0.26), hub, 0.035, COL_PART)
			k.box(Vector3(0.10, 0.12, 0.12), hub, COL_PART)
		# Anti-roll bar: a thin steel bar just behind the front frame, in
		# front of the rear one.
		var bz: float = az + end * 0.36
		_pipe(k, Vector3(-wheel_x + 0.15, d.call(0.045), bz), Vector3(wheel_x - 0.15, d.call(0.045), bz), 0.014, COL_STEEL, 6)

	# Driveline.
	var drive: String = p.get("drive", "rwd")
	var diff_r := Vector3(0.0, hub_y + 0.02, axle_z)
	var diff_f := Vector3(0.0, hub_y + 0.02, -axle_z)
	if drive == "rwd" or drive == "awd":
		# Gearbox tail under the tunnel, the shaft back to the diff with a
		# centre bearing, the diff itself, half-shafts out to the hubs.
		var tail := Vector3(0.0, d.call(0.04), -axle_z + 0.95)
		k.box(Vector3(0.22, 0.14, 0.40), tail, COL_PART)
		_pipe(k, tail + Vector3(0.0, 0.0, 0.2), diff_r + Vector3(0.0, 0.0, -0.18), 0.032, COL_STEEL, 8)
		k.box(Vector3(0.14, 0.10, 0.08), (tail + diff_r) * 0.5, COL_PART)
		_diff(k, diff_r, 0.17)
		_half_shafts(k, diff_r, wheel_x, hub_y, 0.028)
	if drive == "fwd" or drive == "awd":
		# A transverse box behind the front axle, half-shafts to the hubs.
		var box := diff_f + Vector3(0.18, 0.03, 0.22)
		k.box(Vector3(0.62, 0.22, 0.34), box, COL_PART)
		_half_shafts(k, diff_f, wheel_x, hub_y, 0.028)
	if drive == "awd":
		# The transfer case feeds a shaft forward to a front diff.
		_pipe(k, Vector3(0.0, d.call(0.04), -axle_z + 0.75), diff_f + Vector3(0.0, 0.0, 0.17), 0.028, COL_STEEL, 8)
		_diff(k, diff_f, 0.14)

	# Fuel tank: a flat box ahead of the rear axle, off to one side (the
	# exhaust takes the other), plus the spare wheel well behind the axle.
	var tank_x := -0.22 if _exhaust_side(p) > 0.0 else 0.22
	k.box(Vector3(0.80, 0.13, 0.50), Vector3(tank_x, d.call(0.07), axle_z - 0.68), COL_PART)
	# The spare-wheel well behind the axle stays inside the rear overhang: on the
	# kei (0.49 m overhang) and the hatch it reached past the bumper (interior
	# pass, 2026-10-09; tests/fleet/interior_fit.gd).
	var well_room: float = float(p.half_l) - 0.10 - axle_z
	var well_r := clampf(well_room * 0.5, 0.12, 0.30)
	var well_z := minf(axle_z + 0.5, float(p.half_l) - 0.10 - well_r)
	k.cylinder(well_r, -0.05, 0.0, Vector3(0.0, floor_y, well_z), COL_PART, 10)
	# Crossover-style skid plate under the front, when there is room.
	if room > 0.14:
		k.box(Vector3(2.0 * wheel_x - 0.6, 0.02, 0.5), Vector3(0.0, d.call(0.10), -axle_z - 0.1), COL_PART)

	# Exhaust route.
	_exhaust(k, p, role, d)

	# Cop variant: push-bar brackets, two steel arms from the front frame
	# forward and up to the nose.
	if role == ROLE_COP:
		var hl: float = p.half_l
		for side: float in [-1.0, 1.0]:
			_bar(k, Vector3(side * 0.30, d.call(0.06), -axle_z - 0.26), Vector3(side * 0.30, floor_y + 0.10, -hl + 0.06), 0.03, COL_STEEL)
		_bar(k, Vector3(-0.30, floor_y + 0.10, -hl + 0.06), Vector3(0.30, floor_y + 0.10, -hl + 0.06), 0.03, COL_STEEL)
	# Whatever hangs lowest (the tank, the cat) is pressed up to the margin
	# above the road, so nothing scrapes the asphalt at rest.
	k.clamp_above(ground + GROUND_MARGIN)
	return k

## Which side (x sign) the exhaust runs down: the side of the first tip, or
## the right when the tips are centred.
static func _exhaust_side(p: Dictionary) -> float:
	var tips: Array = p.get("tips", [])
	if tips.is_empty():
		return 1.0
	var x: float = _tip_pos(tips[0]).x
	return 1.0 if x >= 0.0 else -1.0

static func _tip_pos(t: Variant) -> Vector3:
	if t is Dictionary:
		return t.pos
	return t

## Down-pipe from the manifold, the cat, the mid pipe along one side of the
## tunnel, the muffler ahead of the rear axle, then one tail pipe to each tip.
static func _exhaust(k: CockpitKit, p: Dictionary, role: String, d: Callable) -> void:
	var axle_z: float = p.axle_z
	var floor_y: float = p.floor_y
	var side := _exhaust_side(p)
	var tips: Array = p.get("tips", [])
	var r := 0.028
	var pipe_y: float = d.call(0.05)
	var x := side * 0.30
	# Down-pipe: drops from the engine (under the hood, ahead of the floor)
	# to the pipe line.
	var manifold := Vector3(side * 0.22, floor_y + 0.16, -axle_z + 0.30)
	var p0 := Vector3(x, pipe_y, -axle_z + 0.75)
	_pipe(k, manifold, p0, r, COL_STEEL, 8)
	# Cat: a fat can.
	var cat0 := p0
	var cat1 := p0 + Vector3(0.0, 0.0, 0.40)
	_pipe(k, cat0, cat1, 0.06, COL_PART, 8)
	# Mid pipe to the muffler.
	var straight := role == ROLE_COP and String(p.get("variant", "")) == "interceptor"
	var muf0 := Vector3(x, pipe_y, axle_z - 1.0)
	var muf1 := Vector3(x, pipe_y, axle_z - 0.45)
	_pipe(k, cat1, muf0, r, COL_STEEL, 8)
	if straight:
		# Interceptor: no muffler, a straight pipe through.
		_pipe(k, muf0, muf1, r, COL_STEEL, 8)
	else:
		k.box(Vector3(0.22, 0.15, muf1.z - muf0.z), (muf0 + muf1) * 0.5, COL_PART)
	# Over the rear axle and out to each tip.
	var over := Vector3(x, pipe_y + 0.03, axle_z + 0.12)
	_pipe(k, muf1, over, r, COL_STEEL, 8)
	if tips.is_empty():
		_pipe(k, over, over + Vector3(0.0, 0.0, 0.5), r, COL_STEEL, 8)
		return
	for t in tips:
		var tip := _tip_pos(t)
		var tr: float = t.r if t is Dictionary else r
		# Keep the tail pipe just inside the tip, which the body already draws.
		_pipe(k, over, tip - Vector3(0.0, 0.0, 0.06), minf(r, tr), COL_STEEL, 8)

static func _diff(k: CockpitKit, at: Vector3, size: float) -> void:
	# A round pumpkin with a finned cover behind it.
	k.cylinder(size * 0.55, -size * 0.5, size * 0.5, at, COL_PART, 8, Basis(Vector3.RIGHT, PI * 0.5))
	k.box(Vector3(size * 0.9, size * 0.9, 0.04), at + Vector3(0.0, 0.0, size * 0.55), COL_PART)

static func _half_shafts(k: CockpitKit, at: Vector3, wheel_x: float, hub_y: float, r: float) -> void:
	for side: float in [-1.0, 1.0]:
		_pipe(k, at + Vector3(side * 0.12, 0.0, 0.0), Vector3(side * (wheel_x - 0.16), hub_y, at.z), r, COL_STEEL, 6)

## A square-section bar between two points.
static func _bar(k: CockpitKit, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		return
	k.box(Vector3(t, t, len), (a + b) * 0.5, col, _along(dir / len))

## A round pipe between two points.
static func _pipe(k: CockpitKit, a: Vector3, b: Vector3, r: float, col: Color, sides := 8) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		return
	# CockpitKit cylinders run along local +y; turn +y onto the pipe.
	var y := dir / len
	var basis := _along(y)
	basis = Basis(basis.x, basis.z, -basis.y)   # z -> y
	k.cylinder(r, -len * 0.5, len * 0.5, (a + b) * 0.5, col, sides, basis)

## A basis whose local +z points along `dir`.
static func _along(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	return Basis(x, y, dir)

# ---------- LOD1 ----------

## The distant underside: one dark plate and the diff lump.
static func build_plate_mesh(p: Dictionary) -> ArrayMesh:
	var k := build_plate_kit(p)
	return k.commit()

static func build_plate_kit(p: Dictionary) -> CockpitKit:
	var k := CockpitKit.new()
	var half_w: float = p.half_w
	var axle_z: float = p.axle_z
	var floor_y: float = p.floor_y
	var room: float = maxf(floor_y - float(p.ground_y) - GROUND_MARGIN, 0.04)
	var drop := minf(room, 0.05)
	k.box(Vector3(2.0 * half_w - 0.32, 0.04, 2.0 * axle_z - 0.5), Vector3(0.0, floor_y - 0.02, 0.0), COL_PAN)
	k.box(Vector3(0.3, drop, 0.3), Vector3(0.0, floor_y - drop * 0.5, axle_z), COL_PART)
	return k
