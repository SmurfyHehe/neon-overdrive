extends SceneTree

# The required-slot check (car-parts-every-vehicle plan 2026-10-10, Roy
# 1171-1180), headless. Builds every vehicle that exists in code the way the
# game does and fails when one leaves a required part empty:
# - every player car (as PlayerCar), every cop and traffic car, and every
#   player-sheet car as an AI car (a rival or crew car): CarSlots.missing()
#   must be empty for its class
#   (player/cop: brakes behind every wheel, brake + third brake + reverse +
#   indicator + hazard lamps, plates front and back; traffic: all but brakes)
# - the check really fails: a car with no parts (the #63 test box) reports
#   its missing slots
# - brakes: the Bug has drums on all four, the hatch/kei drums behind,
#   discs everywhere else; the first brake upgrade leaves no drum
# - lamp lenses sit where they should: plates on the centre line at the rear
#   and front, reverse lamps one each side of the rear, the third brake light
#   high on the rear glass, tags in the glow surface match the counts
# - lamps light: the brake pedal, reverse gear, the indicators (one side) and
#   the hazards (all) change the body's lamp channels; an indicator cancels
#   after the turn
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/required_slots.gd

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

var logger := ErrorCounter.new()
var fails := 0
var checked := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	_run()

func _run() -> void:
	_floor_node()
	await _players()
	await _ai_cars()
	await _negative()
	_brake_rules()
	_parts_built_rule()
	await _lamps_light()
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("required_slots: %d cars checked" % checked)
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _floor_node() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (CarSpec.WORLD_LAYER - 1)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(body)

## Player cars built for a check stay in the tree until the test ends, each in
## its own spot. Freeing one with its sounds playing and then building a
## different car hangs Godot's audio thread (headless, Dummy driver: the main
## thread waits forever on the audio lock in AudioDsp.cached, 2026-10-11). The
## game's own car swap reloads the scene and does not hang (checked p0->p7,
## p1->p2, p7->p1 through GameState.restart).
var _parked: Array[Node] = []

func _park(car: Node3D) -> void:
	car.process_mode = Node.PROCESS_MODE_DISABLED
	_parked.append(car)

func _player(kind: String) -> PlayerCar:
	PlayerCars.selected = kind
	var p: PlayerCar = load("res://scripts/car/player.gd").new()
	p.position = Vector3(-8.0 * _parked.size() - 12.0, 0.6, 20.0)
	root.add_child(p)
	await process_frame
	return p

# ---------- every vehicle, by class ----------

func _players() -> void:
	for k in PlayerCars.KINDS:
		var kind: String = k.id
		var p := await _player(kind)
		_assert_car("player " + kind, p, kind, p.chassis_visual)
		_fittings_sane(kind, p.chassis_visual)
		_park(p)
	PlayerCars.selected = PlayerCars.DEFAULT

func _ai_cars() -> void:
	# Cops and traffic, and every player-sheet car used as a rival or crew car.
	var kinds: Array = []
	for k in NpcCarBuilder.KINDS:
		kinds.append(k)
	var x := 4.0
	for kind in kinds:
		var t := TrafficCar.new()
		t.kind = kind
		t.build = "stock"
		t.position = Vector3(x, 0.6, 0.0)
		x += 4.0
		root.add_child(t)
		await process_frame
		_assert_car("ai " + kind, t, kind, t.chassis_visual)
		_fittings_sane(kind, t.chassis_visual)
		if CarSlots.class_of(kind) != CarSlots.CLASS_TRAFFIC:
			_check(t.get_node_or_null("CarParts") != null, "%s is a cop or rival-capable car: it should carry brakes" % kind)
		else:
			_check(t.get_node_or_null("CarParts") == null, "%s is traffic: wheels only, no brakes (decided)" % kind)
		t.free()

func _assert_car(label: String, vehicle: Node, kind: String, visual: Node3D) -> void:
	checked += 1
	var missing := CarSlots.missing(vehicle, kind, visual)
	_check(missing.is_empty(), "%s (%s) is missing: %s" % [label, CarSlots.class_of(kind), missing])

## The lenses and plates sit where their names say (design coordinates).
func _fittings_sane(kind: String, visual: Node3D) -> void:
	var pts: Dictionary = visual.get_meta("fitting_points", {})
	var rear: Array = pts.get("plate_rear", [])
	var front: Array = pts.get("plate_front", [])
	if rear.size() == 1:
		var p: Vector3 = rear[0]
		_check(p.z > 0.8 and absf(p.x) < 0.02 and p.y > 0.15 and p.y < 1.0, "%s rear plate should be on the centre line at the back, got %s" % [kind, p])
	if front.size() == 1:
		var p: Vector3 = front[0]
		_check(p.z < -0.8 and absf(p.x) < 0.02 and p.y > 0.15 and p.y < 1.0, "%s front plate should be on the centre line at the front, got %s" % [kind, p])
	var rev: Array = pts.get("reverse", [])
	if rev.size() == 2:
		_check(float((rev[0] as Vector3).x) * float((rev[1] as Vector3).x) < 0.0 and (rev[0] as Vector3).z > 0.8,
			"%s reverse lamps should be one each side of the rear" % kind)
	var third: Array = pts.get("third_brake", [])
	if third.size() == 1:
		var tb: Vector3 = third[0]
		_check(tb.z > -0.8 and tb.y > 0.9 and absf(tb.x) < 0.02, "%s third brake light should be high on the rear glass, got %s" % [kind, tb])
	# The glow surface's alpha tags match the counts: two triangles a lens.
	var body := visual.get_node("Body") as MeshInstance3D
	var tags := {7: 0, 8: 0, 9: 0}   # alpha x 10: indicator, third brake, reverse
	for s in body.mesh.get_surface_count():
		if body.mesh.surface_get_name(s) != "glow":
			continue
		var arrays := body.mesh.surface_get_arrays(s)
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		# A parts body is indexed: a triangle's first corner is every third index.
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var n: int = (idx as PackedInt32Array).size() / 3 if idx != null else cols.size() / 3
		for i in n:
			var a := int(round(cols[(idx as PackedInt32Array)[i * 3] if idx != null else i * 3].a * 10.0))
			if tags.has(a):
				tags[a] += 1
	var fit: Dictionary = visual.get_meta("fittings", {})
	_check(int(fit.get("tris", 0)) > 0 and int(fit.get("tris", 0)) <= 150, "%s: the added lenses and plates should be 1..150 triangles, got %d" % [kind, int(fit.get("tris", 0))])
	if CarAssembler.surface_index(body.mesh, "trim") >= 0:
		# A body from parts models its own lamps (CarAssembler.GLOW_TAGS tags
		# them): every lamp the slots count has lens triangles of its kind.
		_check(tags[9] >= int(fit.get("reverse", 0)) * 2, "%s: %d reverse-tagged triangles for %d lenses" % [kind, tags[9], int(fit.get("reverse", 0))])
		_check(tags[8] >= int(fit.get("third_brake", 0)) * 2, "%s: %d brake-lamp triangles for %d lenses" % [kind, tags[8], int(fit.get("third_brake", 0))])
		_check(tags[7] >= 2, "%s: %d indicator triangles" % [kind, tags[7]])
	else:
		_check(tags[9] == int(fit.get("reverse", 0)) * 2, "%s: %d reverse-tagged triangles for %d lenses" % [kind, tags[9], int(fit.get("reverse", 0))])
		_check(tags[8] == int(fit.get("third_brake", 0)) * 2, "%s: %d third-brake triangles for %d lenses" % [kind, tags[8], int(fit.get("third_brake", 0))])

# ---------- the check can fail ----------

func _negative() -> void:
	# The neutral #63 test box has no brakes, plates or extra lamps.
	OS.set_environment("NEON_TEST_CAR", "1")
	var p: PlayerCar = load("res://scripts/car/player.gd").new()
	p.position = Vector3(-6.0, 0.6, 0.0)
	root.add_child(p)
	await process_frame
	var missing := CarSlots.missing(p, "p1_coupe", p.chassis_visual)
	_check(missing.size() >= 6, "a car with no fittings should report its missing slots, got %s" % [missing])
	_check("brake_front (MISSING)" in missing and "plate_rear (MISSING)" in missing,
		"the missing list should name the brake and plate slots: %s" % [missing])
	_park(p)
	OS.set_environment("NEON_TEST_CAR", "")

# ---------- brakes ----------

func _brake_rules() -> void:
	var bug := CarFittings.brakes_for("p0_beater")
	_check(bug.front == "drum" and bug.rear == "drum", "the Bug keeps drums on all four, got %s" % [bug])
	for kind in ["p2_hothatch", "p4_kei"]:
		var b := CarFittings.brakes_for(kind)
		_check(b.front == "disc" and b.rear == "drum", "%s has front discs and rear drums, got %s" % [kind, b])
	for kind in ["p1_coupe", "p3_tuner", "p5_muscle", "p6_crossover", "p10_truck", "c1_patrol", "c2_patrolsuv", "c3_interceptor"]:
		var b := CarFittings.brakes_for(kind)
		_check(b.front == "disc" and b.rear == "disc", "%s has discs all round, got %s" % [kind, b])
	for kind in CarFittings.BRAKES:
		var up := CarFittings.brakes_for(kind, true)
		_check(up.front == "disc" and up.rear == "disc", "the disc upgrade leaves no drum on %s" % kind)
	_check(not CarFittings.has_brakes("n1_commuter"), "traffic has no visible brakes (decided)")
	# A drum is a different mesh from a disc: more triangles in the same wheel.
	var disc := CarParts.wheel_mesh(0.30, 0.205, 0.21, "five", true, "disc")
	var drum := CarParts.wheel_mesh(0.30, 0.205, 0.21, "five", true, "drum")
	_check(disc != drum, "a drum wheel mesh is not the disc one")
	var cols: PackedColorArray = drum.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var glow := 0
	for i in cols.size() / 3:
		if absf(cols[i * 3].a - 0.5) < 0.01:
			glow += 1
	_check(glow >= 24, "a drum carries heat-glow faces (alpha 0.5), got %d" % glow)
	_check(drum.surface_get_array_len(0) / 3 < 1200, "a drum wheel stays cheap")

# ---------- lamps light ----------

func _param(visual: Node3D, name: String) -> float:
	return float((visual.get_node("Body") as MeshInstance3D).get_instance_shader_parameter(name))

func _lamps_light() -> void:
	for kind in ["p1_coupe", "p2_hothatch"]:
		var p := await _player(kind)
		var lamps := p.get_node("CarLamps") as CarLamps
		var v: Node3D = p.chassis_visual
		_check(lamps != null, "%s should carry CarLamps" % kind)
		p.brake_input = 0.0
		p.current_gear = 1
		lamps.apply()
		# "turn" is NpcCarBuilder's state: 0 off, 1 left, 2 right, 3 both (hazard).
		_check(_param(v, "brake") == 0.0 and _param(v, "reverse") == 0.0 and _param(v, "turn") == 0.0,
			"%s: every lamp function starts off" % kind)
		p.brake_input = 1.0
		lamps.apply()
		_check(_param(v, "brake") == 1.0, "%s: the brake pedal lights the brake lamps" % kind)
		p.brake_input = 0.0
		p.current_gear = -1
		lamps.apply()
		_check(_param(v, "reverse") == 1.0 and _param(v, "brake") == 0.0, "%s: reverse gear lights the reverse lamps" % kind)
		p.current_gear = 1
		lamps.toggle_left()
		lamps.apply()
		_check(_param(v, "turn") == NpcCarBuilder.TURN_LEFT, "%s: left indicator lights the left side only" % kind)
		lamps.toggle_right()
		lamps.apply()
		_check(_param(v, "turn") == NpcCarBuilder.TURN_RIGHT, "%s: right replaces left" % kind)
		lamps.toggle_hazard()
		lamps.apply()
		_check(_param(v, "turn") == NpcCarBuilder.TURN_BOTH, "%s: the hazard key lights all four" % kind)
		lamps.toggle_hazard()
		lamps.apply()
		_check(_param(v, "turn") == NpcCarBuilder.TURN_RIGHT, "%s: pressed again, the hazards go off (the right indicator is still on)" % kind)
		# Self-cancel: steer round the corner, straighten out.
		p.steering_input = 0.8
		lamps._self_cancel()
		_check(lamps.turn_right, "%s: the indicator stays on through the corner" % kind)
		p.steering_input = 0.02
		lamps._self_cancel()
		lamps.apply()
		_check(not lamps.turn_right and _param(v, "turn") == 0.0, "%s: the indicator cancels once straight" % kind)
		_park(p)
	PlayerCars.selected = PlayerCars.DEFAULT

## A kind whose body is built from parts gets no generated meshes.
func _parts_built_rule() -> void:
	var kind := "p9_test_parts"
	CarFittings.PARTS_BUILT.append(kind)
	var tris := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var out := CarFittings.build(kind + "|stock", tris, PackedByteArray([0]), ["paint"], [], [], {})
	CarFittings.PARTS_BUILT.erase(kind)
	_check(out.body[0].is_empty() and out.glow[0].is_empty() and int(out.counts.get("plate_rear", 0)) == 0,
		"a parts-built body should get no generated lenses or plates")
	_check(not CarFittings.parts_built("p2_hothatch"), "the proxy bodies are not parts-built")
