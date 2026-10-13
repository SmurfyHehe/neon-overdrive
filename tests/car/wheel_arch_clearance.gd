extends SceneTree

# Wheels never through the body (Roy 1513, issue #670), headless. For every
# player car, built the way the game builds it and settled on a floor:
# - measures, on the real body triangles, how far each drawn tyre can rise
#   from its rest height before its tread ring crosses the body (straight
#   ahead, and the fronts at full lock): the car's measured clearance
# - at rest no tyre is already through the body
# - the visual stop (CarParts.arch_limit) holds: with the spring fully
#   compressed (a landing) the drawn tyre stays inside that measured
#   clearance, within TOL; and it never draws the tyre lower than the sim
#   puts it while the spring is near its rest length (no stop in normal
#   driving)
# - the player's hidden design wheel is an empty placeholder (issue #649)
# - the tyre sizes follow the car's class (CarFittings.TYRES, issue #648):
#   muscle and Camel tall sidewalls, coupe and drift coupe thin
# Prints one line per car with the numbers. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/wheel_arch_clearance.gd

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

## How far (m) a drawn tyre may sit past the measured body line: the tread's
## shoulder bevel is not sampled, so 5 mm is still air.
const TOL := 0.005
## Ring samples: degrees either side of top-dead-centre (the part of the tyre
## under the fender), on the outer face and the middle of the tread.
const RING_DEG := 60
const RING_STEP := 10
## The stop may sit at most this far under the measured arch line (the data
## is 3 mm under it, and a settle scatters 2 mm either way).
const MAX_SLACK := 0.008
## Tyres whose top already touches the arch at rest are drawn this much lower
## than the sim's hub at most (the rear springs sag deeper than the sheets'
## ride height). Over it the tyre visibly sinks into the road: KNOWN lists
## the cars that do, with their issue, and fails if one of them stops doing it.
const MAX_HELD_REST := 0.03
const KNOWN := {"ai p0_beater": "issue #694"}

var logger := ErrorCounter.new()
## Debug (NEON_ARCH_DEBUG=1): which node each collected triangle came from.
var _tri_src: Array[String] = []
var _debug := OS.get_environment("NEON_ARCH_DEBUG") == "1"
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	_run()

func _run() -> void:
	_tyre_sizes()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 << (CarSpec.WORLD_LAYER - 1)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var x := -190.0
	var only := OS.get_environment("NEON_ARCH_CAR")
	for k in PlayerCars.KINDS:
		if only != "" and String(k.id) != only:
			continue
		PlayerCars.selected = String(k.id)
		var p: PlayerCar = load("res://scripts/car/player.gd").new()
		await _measure(p, String(k.id), "player", x)
		x += 8.0
	# Cops and every player car as a rival or crew car: the sheet body and
	# the sheet's own rest height, so measured apart (CarFittings.TYRES ai).
	for kind in CarFittings.TYRES:
		if (only != "" and kind != only) or not NpcCarBuilder.is_npc(kind):
			continue   # the coupe is never an AI car (no sheet in NpcCarBuilder)
		var t := TrafficCar.new()
		t.kind = kind
		t.build = "stock"
		await _measure(t, kind, "ai", x)
		x += 8.0
	PlayerCars.selected = PlayerCars.DEFAULT
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

# ---------- tyre sizes per class ----------

func _tyre_sizes() -> void:
	# Sidewall share of the tyre radius, as CarParts draws it.
	var side := {}
	for kind in CarFittings.TYRES:
		var r := CarFittings.tyre_radius(kind)
		side[kind] = 1.0 - CarFittings.rim_radius(kind, r) / r
		_check(side[kind] > 0.25 and side[kind] < 0.55, "%s: sidewall %.0f%% of the tyre radius is outside a real car's 25-55%%" % [kind, side[kind] * 100.0])
	for tall in ["p5_muscle", "p17_work_pickup"]:
		for thin in ["p1_coupe", "p8_driftcoupe"]:
			_check(side[tall] > side[thin] + 0.08, "%s should have a much taller sidewall than %s (%.0f%% vs %.0f%%)" % [tall, thin, side[tall] * 100.0, side[thin] * 100.0])
	_check(side["p0_beater"] > side["p1_coupe"], "the Bug's tyres should look cheaper (taller) than the coupe's")
	var ratios := {}
	for kind in side:
		ratios[snappedf(side[kind], 0.01)] = true
	_check(ratios.size() >= 6, "tyre profiles should differ per car, got only %d distinct" % ratios.size())
	for k in PlayerCars.KINDS:
		if PlayerCars.SPECIAL_DATA.has(String(k.id)):
			continue   # the specials borrow the coupe's body until their own (issue #660)
		_check(CarFittings.TYRES.has(String(k.id)), "%s has no tyre size in CarFittings.TYRES" % k.id)

# ---------- one car ----------

func _measure(v: Vehicle, kind: String, role: String, x: float) -> void:
	v.position = Vector3(x, 0.6, 0.0)
	root.add_child(v)
	for i in 240:
		await physics_frame
	await process_frame
	var label := "%s %s" % [role, kind]
	var special := PlayerCars.SPECIAL_DATA.has(kind)
	var parts := v.get_node_or_null("CarParts") as CarParts
	_check(parts != null, "%s: no CarParts" % label)
	if parts == null:
		v.free()
		return
	var cv: Node3D = v.get("chassis_visual")
	if v is PlayerCar and NpcCarBuilder.is_npc(kind):
		# Issue #649: the parts car's modelled wheel is not built for the
		# player, whose wheels CarParts draws; child 0 is a bare placeholder.
		var design := v.front_left_wheel.wheel_node.get_child(0) as MeshInstance3D
		_check(design != null and design.mesh == null and not design.visible, "%s: the hidden design wheel should be an empty placeholder" % label)
	var inv := v.global_transform.affine_inverse()
	var wheels: Array[Wheel] = [v.front_left_wheel, v.front_right_wheel, v.rear_left_wheel, v.rear_right_wheel]
	var line := "%s:" % label
	var tops := [INF, INF]
	var held_rest := 0.0
	for i in 4:
		var w := wheels[i]
		var mesh := w.wheel_node.get_node("Parts") as MeshInstance3D
		var hub := (inv * mesh.global_transform).origin
		var tris := _body_tris(cv, inv, w)
		var rest := _free_bump(hub, w.tire_radius, float(parts.cfg.tyre_w) * 0.5, 0.0, tris)
		var lock := INF
		if i < 2:
			var steer := v.max_steering_angle * (1.0 if i == 0 else -1.0)
			lock = _free_bump(hub, w.tire_radius, float(parts.cfg.tyre_w) * 0.5, steer, tris)
		var free := minf(rest, lock)
		var top := hub.y + free + w.tire_radius
		tops[i / 2] = minf(tops[i / 2], top)
		line += " %s %+.0f mm (lock %s)," % [["FL", "FR", "RL", "RR"][i], rest * 1000.0, "-" if i >= 2 else "%+.0f" % (lock * 1000.0)]
		if special:
			continue
		# The stop: with the spring fully compressed (a landing) the drawn hub
		# stays at or under the measured line, the tyre inside the arch.
		var limit := parts.arch_limit(i)
		var hub_sim_rest := w.position.y + w.wheel_node.position.y
		var drawn_full := minf(w.position.y, limit)
		_check(drawn_full + w.tire_radius <= top + TOL, "%s wheel %d: at full bump the drawn tyre goes %.0f mm into the body" % [label, i, (drawn_full + w.tire_radius - top) * 1000.0])
		held_rest = maxf(held_rest, hub_sim_rest - limit)
	# ...and it is not set needlessly low: the wheel keeps its travel. One
	# stop per axle, at its tighter side (some arches differ left to right).
	if not special:
		for i in 4:
			var stop_top := parts.arch_limit(i) + wheels[i].tire_radius
			_check(stop_top >= tops[i / 2] - MAX_SLACK, "%s wheel %d: the stop holds the tyre %.0f mm below the arch (stop %.3f, measured %.3f)" % [label, i, (tops[i / 2] - stop_top) * 1000.0, stop_top, tops[i / 2]])
	line += " arch top f %.3f r %.3f, held at rest %.0f mm" % [tops[0], tops[1], maxf(held_rest, 0.0) * 1000.0]
	if special:
		line += " (placeholder body, no stop: issue #660)"
	print(line)
	if not special:
		if KNOWN.has(label):
			_check(held_rest > MAX_HELD_REST, "%s is listed in KNOWN (%s) but no longer sits into its arch at rest: take it off the list" % [label, KNOWN[label]])
			print("  known: %s rear sits %.0f mm into its arch at rest (%s)" % [label, held_rest * 1000.0, KNOWN[label]])
		else:
			_check(held_rest <= MAX_HELD_REST, "%s: at rest a tyre is held %.0f mm below the sim's hub (it already sits into the arch)" % [label, held_rest * 1000.0])
		# Live: compress the FL spring all the way and let CarParts draw it.
		var fl := v.front_left_wheel
		v.set_physics_process(false)
		fl.spring_current_length = 0.0
		fl._process(0.0)
		parts._process(0.0)
		var mesh := fl.wheel_node.get_node("Parts") as MeshInstance3D
		var hub_drawn := (v.global_transform.affine_inverse() * mesh.global_transform).origin.y
		_check(hub_drawn <= parts.arch_limit(0) + 1e-4, "%s: the live stop should hold the drawn FL hub at %.3f, got %.3f" % [label, parts.arch_limit(0), hub_drawn])
	v.free()

## Body triangles near one wheel, car space. Everything the chassis visual
## draws except the underside (its arms and pipes sit inside the arch).
func _body_tris(cv: Node3D, inv: Transform3D, w: Wheel) -> PackedVector3Array:
	var out := PackedVector3Array()
	_tri_src.clear()
	var reach := w.tire_radius + 0.35
	var c := w.position
	var box := AABB(Vector3(c.x - 0.6, c.y - reach - 0.4, c.z - reach), Vector3(1.2, reach * 2.0 + 0.4, reach * 2.0))
	var stack: Array[Node] = [cv]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == Undercarriage.NODE_NAME:
			continue
		for ch in n.get_children():
			stack.append(ch)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := inv * mi.global_transform
		var m := mi.mesh
		for s in m.get_surface_count():
			if m is ArrayMesh and (m as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n_tri := idx.size() / 3 if idx.size() > 0 else v.size() / 3
			for t in n_tri:
				var a := xf * v[idx[t * 3] if idx.size() > 0 else t * 3]
				var b := xf * v[idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1]
				var d := xf * v[idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2]
				var tb := AABB(a, Vector3.ZERO).expand(b).expand(d)
				if tb.intersects(box):
					out.append(a)
					out.append(b)
					out.append(d)
					_tri_src.append(String(cv.get_path_to(mi)) + "#%d" % s)
	return out

## How far (m) a drawn tyre (hub in car space) can rise from where it is now before
## its tread ring crosses a body triangle; negative when it already does.
## `steer` turns the wheel about its vertical axis (full lock).
func _free_bump(hub: Vector3, r: float, hw: float, steer: float, tris: PackedVector3Array) -> float:
	var basis := Basis(Vector3.UP, steer)
	var lo := -0.15
	var hi := 0.0
	if not _hits(hub, r, hw, basis, tris):
		lo = 0.0
		hi = 0.02
		while hi < 0.4 and not _hits(hub + Vector3(0.0, hi, 0.0), r, hw, basis, tris):
			lo = hi
			hi += 0.02
		if hi >= 0.4:
			return 0.4
	elif _hits(hub + Vector3(0.0, lo, 0.0), r, hw, basis, tris):
		return lo
	for it in 10:
		var mid := (lo + hi) * 0.5
		if _hits(hub + Vector3(0.0, mid, 0.0), r, hw, basis, tris):
			hi = mid
		else:
			lo = mid
	return lo

func _hits(hub: Vector3, r: float, hw: float, basis: Basis, tris: PackedVector3Array) -> bool:
	# The outer face and the middle of the tread: what shows through a
	# fender. The inner face sits behind the tyre where the arch liner and
	# the floor are meant to be close, and nobody sees it.
	var out_x := hw * signf(hub.x)
	var steer_on := not basis.is_equal_approx(Basis())
	for ax in [out_x, 0.0]:
		var o := hub + basis * Vector3(ax, 0.0, 0.0)
		for deg in range(-RING_DEG, RING_DEG + 1, RING_STEP):
			var a := deg_to_rad(float(deg))
			var q := o + basis * Vector3(0.0, r * cos(a), r * sin(a))
			# At lock half the tread swings inboard, into the arch liner and
			# under the closed shell where no one sees it; only the half that
			# swings out can show through the fender.
			if absf(q.x) < absf(hub.x + out_x) - 0.001 and steer_on:
				continue
			for t in tris.size() / 3:
				var hit: Variant = Geometry3D.segment_intersects_triangle(o, q, tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2])
				if hit != null:
					if _debug:
						print("  hit ax %.3f deg %d at %s (hub %s) on %s" % [ax, deg, hit, hub, _tri_src[t]])
					return true
	return false
