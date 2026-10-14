extends SceneTree

# Exterior fit (better-exteriors note 2026-10-13, section 5, issue #663): the
# outside of every car is checked for parts that do not fit, headless, so a
# clash is caught here and not in a screenshot.
#
# Cars from parts (the glb as CarAssembler reads it, car space, panels shut):
#   door glass   each door's glass hangs on the door's own hinge, so it moves
#                with the door when it opens (the kei's fixed side screens
#                excepted, as its kit builds them), and never stands outside
#                the door skin
#   seals        every window has its rubber seal (glass_<n> -> seal_<n>)
#   float        every small outside part (mirrors, handles, wipers, plates,
#                lamps, antenna, tips) has a vertex within FLOAT_GAP of another
#                part. Measured 2026-10-13: lamps, plates and wipers sit 3-14
#                mm from their neighbours (shut gaps, plate standoffs); the
#                mirrors that fail stand 16-54 mm off the car
#
# Every player car, booted as the player's car (the body actually drawn, the
# wheels CarParts actually draws; sheet cars and specials included):
#   ground       the lowest point of the body is GROUND_MIN above the road
#   proud        the tyre's outer wall stands at most PROUD_MAX outside the
#                body over its arch (the specials stood 11.5 cm out, #660)
#   rest         at rest the tyre reaches no more than REST_TOL into an outside
#                panel (body, fender, bumper, blister, flare, door, strips).
#                How far: the tyre is shrunk about its hub until it clears.
#                Hidden parts (arch liners, underbody, bay, suspension) are
#                printed, not failed
#   bump, lock   printed only: at full bump (spring fully closed) and full lock
#                every car's tyre passes through its arch liner, so these are
#                limits for the suspension and steering, not for the body
#                (#670)
#
# KNOWN holds what this test found on its first run (2026-10-13), each with
# its issue: the test fails if one gets worse, and also once it is fixed, so
# the line comes out and the issue gets closed. Never raise a number here to
# make a change pass; fix the car.
#
# Not checked here yet (#663 keeps them): pop-up lids at open_deg (the pop-ups
# do not move yet, #667), parts sunk through each other in general (glass edges
# tuck under pillars, seals and trim on purpose, so a crossing alone says
# nothing), and the night read of the tail lamps at 7/20/100 m (needs a render).
#
#   godot --headless --audio-driver Dummy --path . -s res://tests/fleet/exterior_fit.gd
# NEON_FIT_CAR=<id> checks one car.
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
## A small part this close to another part (m) is mounted on it.
const FLOAT_GAP := 0.015
## Lowest point of the body above the road at rest (m).
const GROUND_MIN := 0.08
## Door glass may sit this far outside its door skin (m): none.
const GLASS_OUT := 0.001
## The tyre's outer wall may stand this far outside the body over its arch (m).
const PROUD_MAX := 0.02
## How far a resting tyre may reach into an outside panel (m): the drawn
## tyre's rounded shoulder, which the test's square-edged tyre does not have.
const REST_TOL := 0.003
## Segments around the tyre.
const RING := 32
## Small outside parts that must sit on something (name prefixes).
const SMALL := ["mirror_", "handle_", "wiper_", "antenna", "plate_", "head_", "tail_", "turn_",
	"brake_", "reverse_", "fog_", "tip_", "badge", "fuel_flap"]
## Parts that are the outside of the car (name prefixes); a sheet body is "body".
const OUTER := ["body", "fender_", "bumper_", "blister_", "flare_", "door_", "rub_", "arch_lips",
	"skirt", "hood", "trunk", "hatch", "wear", "sill"]
## The kei's door glass is a fixed side screen (its kit).
const FIXED_DOOR_GLASS := ["p4_kei"]

## car -> check -> [measured mm, issue].
const KNOWN := {
	"p1_coupe": {"float mirror_l": [54, 688], "float mirror_r": [54, 688],
		"rest fl": [11, 689], "rest fr": [11, 689], "rest rl": [20, 689], "rest rr": [20, 689]},
	"p2_hothatch": {"float mirror_l": [32, 688], "float mirror_r": [32, 688]},
	"p4_kei": {"float mirror_l": [16, 688], "float mirror_r": [16, 688]},
	"p8_driftcoupe": {"float mirror_l": [34, 688], "float mirror_r": [34, 688],
		"ground": [15, 690], "rest fl": [5, 689], "rest fr": [5, 689], "rest rl": [6, 689], "rest rr": [6, 689]},
	"p10_truck": {"float mirror_l": [24, 688], "float mirror_r": [24, 688], "seal glass_slider": [0, 691]},
	"p0_beater": {"rest fl": [34, 692], "rest fr": [34, 692], "rest rl": [45, 692], "rest rr": [45, 692]},
	"p7_wagon": {"rest fl": [21, 692], "rest fr": [21, 692], "rest rl": [43, 692], "rest rr": [43, 692]},
	"p6_crossover": {"rest rr": [32, 689]},
	"m1_monster": {"rest fl": [16, 689], "rest fr": [16, 689], "rest rl": [35, 689], "rest rr": [35, 689]},
	"l1_lowrider": {"rest fl": [16, 689], "rest fr": [16, 689], "rest rl": [35, 689], "rest rr": [35, 689]},
}

var fails := 0
var logger := Harness.ErrorCounter.new()
var _seen := {}   # "car|check" -> true for every KNOWN entry this run met

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

## A measured problem (mm; 0 = none): fails unless KNOWN lists it at this
## size or worse, and fails when a KNOWN one has gone (fixed: take it out).
func _measure(car: String, check: String, mm: float, what: String) -> void:
	var known: Array = (KNOWN.get(car, {}) as Dictionary).get(check, [])
	if known.is_empty():
		_check(mm <= 0.0, "%s: %s" % [car, what])
		return
	_seen[car + "|" + check] = true
	if mm <= 0.0:
		_check(false, "%s %s is fixed: take it out of KNOWN and close #%d" % [car, check, known[1]])
	elif roundf(mm) > float(known[0]):
		_check(false, "%s: %s (worse than the %d mm known in #%d)" % [car, what, known[0], known[1]])
	else:
		print("  known #%d: %s" % [known[1], what])

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		var car := String(k.id)
		if only != "" and car != only:
			continue
		if CarAssembler.has_car(car):
			await _parts_checks(car)
		await _tyre_checks(car)
	OS.set_environment("NEON_CAR", "")
	for car in KNOWN:
		if only != "" and car != only:
			continue
		for check in KNOWN[car]:
			_check(_seen.has(car + "|" + check), "%s %s is in KNOWN but was not measured" % [car, check])
	_check(logger.errors.is_empty(), "%d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
	print("exterior_fit: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------- cars from parts ----------

func _tris(car: String, part: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mats := CarAssembler.part_arrays(car, part)
	for mn in mats:
		var m: Dictionary = mats[mn]
		var v: PackedVector3Array = m.v
		for k in (m.i as PackedInt32Array):
			out.append(v[k])
	return out

func _hinge_of(car: String, part: String) -> String:
	var hs := CarAssembler.hinges(car)
	for h in hs:
		if part in (hs[h].parts as Array):
			return h
	return ""

func _parts_checks(car: String) -> void:
	var names := CarAssembler.part_names(car)
	# door glass: on the door's hinge, inside the door skin
	for side in ["l", "r"]:
		var glass: String = "glass_door_" + side
		var door: String = "door_" + side
		if not (glass in names) or not (door in names):
			continue
		if not (car in FIXED_DOOR_GLASS):
			var gh := _hinge_of(car, glass)
			_check(gh != "" and gh == _hinge_of(car, door), "%s: %s hangs on '%s', its door on '%s'" % [car, glass, gh, _hinge_of(car, door)])
		var out := absf(_far_x(CarAssembler.part_aabb(car, glass))) - absf(_far_x(CarAssembler.part_aabb(car, door)))
		_check(out <= GLASS_OUT, "%s: %s stands %.1f mm outside its door skin" % [car, glass, out * 1000.0])
	# seals
	for p in names:
		if not p.begins_with("glass_"):
			continue
		var seal := "seal_" + p.trim_prefix("glass_")
		var known: Array = (KNOWN.get(car, {}) as Dictionary).get("seal " + p, [])
		if known.is_empty():
			_check(seal in names, "%s: %s has no %s" % [car, p, seal])
			continue
		_seen[car + "|seal " + p] = true
		if seal in names:
			_check(false, "%s seal %s is fixed: take it out of KNOWN and close #%d" % [car, p, known[1]])
		else:
			print("  known #%d: %s has no %s" % [known[1], p, seal])
	# float: one body per part, a small ball at each vertex of a small part
	var bodies := {}
	for p in names:
		var t := _tris(car, p)
		if not t.is_empty():
			bodies[p] = _shape_body(t, Vector3(0.0, 2000.0, 0.0))
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = FLOAT_GAP
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.margin = 0.0
	var checked := 0
	for p in bodies:
		if not _small(p):
			continue
		checked += 1
		q.exclude = [(bodies[p] as StaticBody3D).get_rid()]
		var touches := false
		for v in _tris(car, p):
			q.transform = Transform3D(Basis(), v + Vector3(0.0, 2000.0, 0.0))
			if not space.intersect_shape(q, 1).is_empty():
				touches = true
				break
		var gap := 0.0 if touches else _nearest(car, p, names)
		_measure(car, "float " + p, gap * 1000.0, "%s floats %.0f mm from the nearest part (at most %.0f)" % [p, gap * 1000.0, FLOAT_GAP * 1000.0])
	print("%s: %d small parts checked for floating" % [car, checked])
	for p in bodies:
		(bodies[p] as Node).queue_free()
	await physics_frame

## Distance from any vertex of `part` to the nearest other part (m).
func _nearest(car: String, part: String, names: PackedStringArray) -> float:
	var pv := _tris(car, part)
	var box := CarAssembler.part_aabb(car, part).grow(0.2)
	var best := INF
	for o in names:
		if o == part or not CarAssembler.part_aabb(car, o).intersects(box):
			continue
		var t := _tris(car, o)
		for k in range(0, t.size(), 3):
			for v in pv:
				best = minf(best, _point_tri(v, t[k], t[k + 1], t[k + 2]))
	return best

static func _point_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := (b - a).cross(c - a)
	if n.length_squared() > 1e-14:
		n = n.normalized()
		var d := (p - a).dot(n)
		var f := p - n * d
		if (b - a).cross(f - a).dot(n) >= 0.0 and (c - b).cross(f - b).dot(n) >= 0.0 and (a - c).cross(f - c).dot(n) >= 0.0:
			return absf(d)
	var m := p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))
	m = minf(m, p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
	return minf(m, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))

func _shape_body(t: PackedVector3Array, at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(t)
	cs.shape = sh
	sb.add_child(cs)
	sb.position = at
	root.add_child(sb)
	return sb

static func _small(p: String) -> bool:
	for s in SMALL:
		if p.begins_with(s):
			return true
	return false

static func _outer(p: String) -> bool:
	for s in OUTER:
		if p.begins_with(s):
			return true
	return false

static func _far_x(box: AABB) -> float:
	return box.end.x if absf(box.end.x) > absf(box.position.x) else box.position.x

# ---------- tyres and ride height, in the game ----------

func _tyre_checks(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	var game := Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	if p == null or p.chassis_visual == null:
		_check(false, "%s: the game should boot with the car" % kind)
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for i in RATE:
		await physics_frame
	var parts := p.get_node_or_null(^"CarParts") as CarParts
	var body := p.chassis_visual.get_node_or_null(^"Body") as MeshInstance3D
	_check(parts != null and body != null, "%s: no CarParts wheels or no Body" % kind)
	if parts == null or body == null:
		game.queue_free()
		await process_frame
		return
	# Everything in the Body's own frame (a parts car's design frame). The
	# body drawn may be another car's (the specials wear the coupe's).
	var inv := body.global_transform.affine_inverse()
	var drawn := String(p.chassis_visual.get_meta("kind", kind))
	var shells := {}
	if CarAssembler.has_car(drawn) and NpcCarBuilder.uses_parts(drawn):
		for pn in CarAssembler.part_names(drawn):
			var t := _tris(drawn, pn)
			if not t.is_empty():
				shells[pn] = t
	else:
		shells["body"] = body.mesh.get_faces()
	var offs := {}
	var nodes := []
	for pn in shells:
		offs[pn] = Vector3(0.0, 500.0 + 8.0 * offs.size(), 0.0)
		nodes.append(_shape_body(shells[pn], offs[pn]))
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var r: float = p.front_tire_radius
	var w: float = parts.cfg.tyre_w
	var wheels := [p.front_left_wheel, p.front_right_wheel, p.rear_left_wheel, p.rear_right_wheel]
	var corners := ["fl", "fr", "rl", "rr"]
	var lock: float = p.max_steering_angle
	var ground := INF
	var hubs := []
	for i in 4:
		var hub: Vector3 = inv * (parts._wheel_meshes_inst[i] as Node3D).global_position
		hubs.append(hub)
		ground = minf(ground, hub.y - r)
	# Ground: the lowest point of the body above the road under the tyres.
	var low := INF
	var low_part := ""
	for pn in shells:
		for v in (shells[pn] as PackedVector3Array):
			if v.y < low:
				low = v.y
				low_part = pn
	var clear := low - ground
	print("%s (%s body): tyre r %.3f w %.3f, lock %.0f deg, lowest %s %.3f m above the road" % [kind, drawn, r, w, rad_to_deg(lock), low_part, clear])
	_measure(kind, "ground", clear * 1000.0 if clear < GROUND_MIN else 0.0,
		"%s is %.3f m above the road (at least %.2f)" % [low_part, clear, GROUND_MIN])
	for i in 4:
		var hub: Vector3 = hubs[i]
		var side := signf(hub.x)
		var travel: float = (wheels[i] as Node).get("spring_current_length")
		# proud: outer wall against the body over the arch
		var fender := 0.0
		for pn in shells:
			for v in (shells[pn] as PackedVector3Array):
				if signf(v.x) == side and absf(v.z - hub.z) <= r and v.y >= hub.y and v.y <= hub.y + r + 0.10:
					fender = maxf(fender, absf(v.x))
		var proud := absf(hub.x) + w * 0.5 - fender
		_check(proud <= PROUD_MAX, "%s %s: the tyre stands %.1f cm outside the body (at most %.0f)" % [kind, corners[i], proud * 100.0, PROUD_MAX * 100.0])
		var poses := {"rest": [0.0, 0.0], "bump": [travel, 0.0]}
		if i < 2:
			poses["lock_l"] = [0.0, lock]
			poses["lock_r"] = [0.0, -lock]
		var line := "  %s hub %s proud %+.1f cm, travel %.2f m:" % [corners[i], str(hub.snappedf(0.001)), proud * 100.0, travel]
		for pose in poses:
			var cut := {}
			for pn in shells:
				var m := _interference(space, offs[pn], hub, r, w, poses[pose][0], poses[pose][1])
				if m > 0.0:
					cut[pn] = m
			var keys := cut.keys()
			keys.sort_custom(func(x, y): return cut[x] > cut[y])
			if pose == "rest":
				var worst := 0.0
				var worst_part := ""
				for pn in keys:
					if _outer(pn) and cut[pn] > worst:
						worst = cut[pn]
						worst_part = pn
				_measure(kind, "rest " + corners[i], worst * 1000.0 if worst > REST_TOL else 0.0,
					"%s tyre reaches %.0f mm into %s at rest (at most %.0f)" % [corners[i], worst * 1000.0, worst_part, REST_TOL * 1000.0])
			if not keys.is_empty():
				var bits := []
				for pn in keys.slice(0, 4):
					bits.append("%s %.0f" % [pn, cut[pn] * 1000.0])
				line += " %s [%s]" % [pose, ", ".join(bits)]
		print(line)
	for n in nodes:
		(n as Node).queue_free()
	game.queue_free()
	await process_frame
	await process_frame

## How far (m of radius) the tyre reaches into one shell: the tyre is shrunk
## about its hub until no segment over its surface crosses the shell; 0 when
## it is clear at full size.
func _interference(space: PhysicsDirectSpaceState3D, base: Vector3, hub: Vector3, r: float, w: float, lift: float, yaw: float) -> float:
	if not _tyre_cuts(space, base, hub, r, w, lift, yaw):
		return 0.0
	var lo := 0.0
	var hi := 1.0
	for it in 8:
		var m := (lo + hi) * 0.5
		if _tyre_cuts(space, base, hub, r * m, w * m, lift, yaw):
			hi = m
		else:
			lo = m
	return (1.0 - lo) * r

## True when a segment over the tyre's surface (both side walls and the
## tread) crosses the shell, with the hub raised `lift` and turned `yaw`.
func _tyre_cuts(space: PhysicsDirectSpaceState3D, base: Vector3, hub: Vector3, r: float, w: float, lift: float, yaw: float) -> bool:
	var b := Basis(Vector3.UP, yaw)
	var c := hub + Vector3(0.0, lift, 0.0)
	var pts := []
	for k in RING:
		var a := TAU * k / RING
		var o := Vector3(0.0, r * cos(a), r * sin(a))
		pts.append([c + b * (o + Vector3(-w * 0.5, 0.0, 0.0)), c + b * (o + Vector3(w * 0.5, 0.0, 0.0))])
	for k in RING:
		var n := (k + 1) % RING
		for seg in [[pts[k][0], pts[n][0]], [pts[k][1], pts[n][1]], [pts[k][0], pts[k][1]]]:
			var q := PhysicsRayQueryParameters3D.create(base + seg[0], base + seg[1])
			q.hit_back_faces = true
			if not space.intersect_ray(q).is_empty():
				return true
	return false
