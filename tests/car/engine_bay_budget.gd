extends SceneTree

# Engine bay budget (engine bays B0, issue #642; budget table in
# notes/engine-bays-better-2026-10-13.md section 5). Checks that
# - the closed body of every car from parts carries no bay part (`engine`,
#   `bay_*`): the shut lid costs 0 triangles and 0 draw calls for the bay, and
#   the closed body keeps the same surfaces it had
# - the bay is its own mesh (CarAssembler.build_bay) with every bay triangle
#   the glb has, within BAY_TRIS triangles and BAY_CALLS draw calls (the
#   hood's open panel, B1, adds one more)
# - the open-panels picture body still shows its bay
# - in the game (the wagon, the free night-one car, driven by the player): no
#   Bay node exists while driving; detail on (photo mode, garage, stopped with
#   a panel open) builds it once under the body, in the body's frame and
#   render layers; detail off hides it again; nothing logs an error
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/car/engine_bay_budget.gd

const CARS := ["p0_beater", "p1_coupe", "p2_hothatch", "p4_kei", "p5_muscle", "p7_wagon", "p8_driftcoupe", "p10_truck"]
const BAY_TRIS := 3000
const BAY_CALLS := 3
const PLAYER_CAR := "p7_wagon"

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

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	_run()

func _run() -> void:
	for id: String in CARS:
		_static(id)
	await _in_game()
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _tris_of(id: String, parts: PackedStringArray) -> int:
	var n := 0
	for p in parts:
		for m: Dictionary in CarAssembler.part_arrays(id, p).values():
			n += (m.i as PackedInt32Array).size() / 3
	return n

func _static(id: String) -> void:
	_check(CarAssembler.has_car(id), "%s: no body.glb" % id)
	var bay_parts := CarAssembler.bay_part_names(id)
	var all := CarAssembler.part_names(id)
	var bay_tris := _tris_of(id, bay_parts)
	var all_tris := _tris_of(id, all)
	var closed := CarAssembler.build(id)
	var closed_tris := CarAssembler._mesh_tris(closed.mesh)
	_check(closed_tris == all_tris - bay_tris, "%s: closed body %d triangles, want %d (all %d minus the bay's %d)" % [
		id, closed_tris, all_tris - bay_tris, all_tris, bay_tris])
	_check(closed.mesh.get_surface_count() <= CarAssembler.SURFACES.size(), "%s: closed body has %d surfaces" % [id, closed.mesh.get_surface_count()])
	_check(closed.get_node_or_null(CarAssembler.BAY_NODE_NAME) == null, "%s: the closed body carries a Bay node" % id)
	var active := CarAssembler.bay_active_names(id)
	var active_tris := _tris_of(id, active)
	var bay := CarAssembler.build_bay(id)
	if bay_parts.is_empty():
		_check(bay == null, "%s: no bay parts but build_bay made a mesh" % id)
		print("%s: no bay parts, body %d triangles" % [id, closed_tris])
	else:
		_check(bay != null and bay.name == CarAssembler.BAY_NODE_NAME, "%s: build_bay made no Bay mesh" % id)
		if bay != null:
			var t := CarAssembler._mesh_tris(bay.mesh)
			var calls := bay.mesh.get_surface_count()
			_check(t == active_tris, "%s: Bay mesh %d triangles, the stock bay parts have %d" % [id, t, active_tris])
			_check(t <= BAY_TRIS, "%s: bay %d triangles, budget %d" % [id, t, BAY_TRIS])
			_check(calls <= BAY_CALLS, "%s: bay %d draw calls, budget %d" % [id, calls, BAY_CALLS])
			print("%s: bay %s, %d triangles, %d draw calls; body %d -> %d triangles while driving" % [
				id, ", ".join(bay_parts), t, calls, all_tris, closed_tris])
			bay.free()
		# the pictures with the lids up still show what is under them
		var open := CarAssembler.build(id, {"panels": "open"})
		var open_tris := CarAssembler.triangle_count(id, {"panels": "open"})
		_check(open_tris == all_tris - bay_tris + active_tris, "%s: open-panels body %d triangles, want %d (the body with the stock bay)" % [id, open_tris, all_tris - bay_tris + active_tris])
		open.free()
		# every set of mods the car can wear at once (B4) stays in budget and
		# draws exactly its parts: the fitted mods' on, what they hide off
		var variants := CarAssembler.bay_variants(id)
		var worst := 0
		for keys: Array in FittedMods.combos(id, variants):
			var names := CarAssembler.bay_active_names(id, keys)
			var want := _tris_of(id, names)
			var b := CarAssembler.build_bay(id, null, keys)
			var t := CarAssembler._mesh_tris(b.mesh)
			_check(t == want, "%s with %s: Bay mesh %d triangles, its parts have %d" % [id, keys, t, want])
			_check(t <= BAY_TRIS, "%s with %s: bay %d triangles, budget %d" % [id, keys, t, BAY_TRIS])
			_check(b.mesh.get_surface_count() <= BAY_CALLS, "%s with %s: bay %d draw calls, budget %d" % [id, keys, b.mesh.get_surface_count(), BAY_CALLS])
			for k in keys:
				for pname: String in variants[k].parts:
					_check(names.has(pname) or _hidden_by(variants, keys, pname), "%s with %s: %s should be drawn" % [id, keys, pname])
				for pname: String in variants[k].hides:
					_check(not names.has(pname), "%s with %s: %s should be off the bay" % [id, keys, pname])
			worst = maxi(worst, t)
			b.free()
		if not variants.is_empty():
			print("%s: %d mod variants, %d fitted sets, worst %d triangles" % [id, variants.size(), FittedMods.combos(id, variants).size(), worst])
	closed.free()

## True when another fitted key hides this part (a big single over the small turbo).
func _hidden_by(variants: Dictionary, keys: Array, pname: String) -> bool:
	for k in keys:
		if (variants[k].hides as PackedStringArray).has(pname):
			return true
	return false

func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (CarSpec.WORLD_LAYER - 1)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(0.0, -0.5, 0.0)
	return body

func _in_game() -> void:
	root.add_child(_floor())
	var gs := GameState.new()
	root.add_child(gs)
	CarDetail.bind_state(gs)
	var player: PlayerCar = load("res://scripts/car/player.gd").new()
	player.chassis = PLAYER_CAR
	player.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(player)
	await process_frame
	await process_frame
	var body := CarAssembler.body_of(player)
	_check(body != null and String(body.get_meta("car_id", "")) == PLAYER_CAR, "the player's %s is not a car from parts" % PLAYER_CAR)
	if body == null:
		return
	var detail := CarDetail.of(player)
	_check(not detail.on, "detail is on while driving")
	_check(body.get_node_or_null(CarAssembler.BAY_NODE_NAME) == null, "a Bay node exists while driving")
	_check(detail.node_of("bay") == null, "the bay was built before anyone looked")

	# photo mode builds it, once, under the body
	gs.state = GameState.State.PHOTO
	gs.state_changed.emit(GameState.State.PHOTO, GameState.State.PLAYING)
	var bay := body.get_node_or_null(CarAssembler.BAY_NODE_NAME) as MeshInstance3D
	_check(bay != null and bay.visible, "photo mode shows no bay")
	if bay != null:
		_check(detail.node_of("bay") == bay, "CarDetail does not know the bay it built")
		_check(bay.transform == Transform3D.IDENTITY, "the bay is not in the body's frame: %s" % bay.transform)
		_check(bay.layers == body.layers, "the bay is on render layers %d, the body on %d" % [bay.layers, body.layers])
		_check(CarAssembler._mesh_tris(bay.mesh) == _tris_of(PLAYER_CAR, CarAssembler.bay_part_names(PLAYER_CAR)), "the bay in the game is not the whole bay")
	gs.state = GameState.State.PLAYING
	gs.state_changed.emit(GameState.State.PLAYING, GameState.State.PHOTO)
	_check(bay != null and not bay.visible, "leaving photo mode leaves the bay showing")

	# stopped with a panel open: shown again, the same node
	detail.panel_open = true
	player.speed = 0.0
	detail.refresh()
	_check(bay != null and bay.visible and body.get_node_or_null(CarAssembler.BAY_NODE_NAME) == bay, "a panel open while stopped does not show the same bay")
	_check(body.get_children().filter(func(n: Node) -> bool: return n.name.begins_with(CarAssembler.BAY_NODE_NAME)).size() == 1, "the bay was built twice")
	detail.panel_open = false
	detail.refresh()
	_check(bay != null and not bay.visible, "shut again, the bay still shows")
	player.queue_free()
	await process_frame
