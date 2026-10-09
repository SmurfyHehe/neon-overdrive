extends SceneTree

# Hidden unseen parts (hide-unseen-parts plan 2026-10-09, Part 1), headless.
# Checks that
# - a car's detail parts (today the shocks) do not exist while driving: no
#   node, no draw call, and CarParts skips their per-frame transforms
# - detail turns on in photo mode (GameState.PHOTO) at once, in the garage
#   view, and when the car is stopped with a panel open, but not with a panel
#   open at speed; it builds the part once and hides it after
# - the undercarriage keeps its LOD on the player (real set to LOD0_END, plate
#   to LOD1_END) and the Low preset hides it unless detail is on
# - a traffic car gets no CarDetail node; a cop (underside + parts) does
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/car_detail.gd

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
	await _player()
	await _traffic()
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

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

func _player() -> void:
	root.add_child(_floor())
	var gs := GameState.new()
	root.add_child(gs)
	CarDetail.bind_state(gs)
	var player: PlayerCar = load("res://scripts/car/player.gd").new()
	player.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(player)
	await process_frame
	var detail := CarDetail.of(player)
	_check(detail != null and detail.get_parent() == player, "the player carries a CarDetail node")
	_check(not detail.on, "detail is off while driving")
	_check(player.get_node_or_null("Shocks") == null, "no shocks node exists while driving")
	var parts := player.get_node_or_null("CarParts") as CarParts
	_check(parts != null and parts.triangle_count() > 0, "the parts still count wheels and calipers")

	# Photo mode: on at once (the signal), built, shown.
	gs.state = GameState.State.PHOTO
	gs.state_changed.emit(GameState.State.PHOTO, GameState.State.PLAYING)
	_check(detail.on, "photo mode turns detail on at once")
	var shocks := player.get_node_or_null("Shocks") as MultiMeshInstance3D
	_check(shocks != null and shocks.visible, "photo mode builds and shows the shocks")
	_check(detail.node_of("shocks") == shocks, "node_of finds the built part")
	# Their transforms follow the springs once they exist.
	for i in 60:
		await physics_frame
	await process_frame
	if shocks != null:
		var st := shocks.multimesh.get_instance_transform(0)
		_check(st.basis.y.length() > 0.02 and absf(st.origin.z - player.front_left_wheel.position.z) > 0.3, "the shock transforms are written while shown (%s)" % st)
	gs.state = GameState.State.PLAYING
	gs.state_changed.emit(GameState.State.PLAYING, GameState.State.PHOTO)
	_check(not detail.on and shocks != null and not shocks.visible, "leaving photo mode hides the shocks")

	# Garage view.
	CarDetail.garage = true
	detail.refresh()
	_check(detail.on and shocks.visible, "the garage view turns detail on")
	CarDetail.garage = false
	detail.refresh()
	_check(not detail.on, "and off again when it closes")

	# Stopped with a panel open: on. The same panel open at speed: off.
	detail.panel_open = true
	player.speed = 0.0
	detail.refresh()
	_check(detail.on, "stopped with a panel open shows the detail parts")
	player.speed = 3.0
	detail.refresh()
	_check(not detail.on, "a panel open at 3 m/s does not (the car drove off)")
	detail.panel_open = false
	player.speed = 0.0
	detail.refresh()
	_check(not detail.on, "stopped with everything shut: off")

	# The poll: detail follows a state change without the signal within POLL_SECS.
	CarDetail.garage = true
	for i in 30:
		await process_frame
	_check(detail.on, "the poll picks up the garage flag")
	CarDetail.garage = false
	for i in 30:
		await process_frame
	_check(not detail.on, "and drops it")

	# The underside: LOD on the player, hidden on Low unless detail is on.
	var under := player.chassis_visual.get_node_or_null(Undercarriage.NODE_NAME) as MeshInstance3D
	var plate := player.chassis_visual.get_node_or_null(Undercarriage.PLATE_NAME) as MeshInstance3D
	_check(under != null and plate != null, "the player's chassis carries the underside and its plate")
	if under != null and plate != null:
		_check(is_equal_approx(under.visibility_range_end, Undercarriage.LOD0_END) and is_equal_approx(plate.visibility_range_end, Undercarriage.LOD1_END), "the player's underside has the distance LOD")
		_check(under.visible and plate.visible, "Medium shows the underside")
		var was := GraphicsSettings.preset
		GraphicsSettings.preset = "low"
		GraphicsSettings.apply(self)
		_check(not under.visible and not plate.visible, "Low hides the underside and its plate")
		CarDetail.garage = true
		detail.refresh()
		_check(under.visible and plate.visible, "but detail on shows it again on Low")
		CarDetail.garage = false
		detail.refresh()
		_check(not under.visible, "and detail off hides it again on Low")
		GraphicsSettings.preset = was
		GraphicsSettings.apply(self)
		_check(under.visible and plate.visible, "back on %s it shows" % was)
	player.queue_free()
	await process_frame

func _traffic() -> void:
	var plain := TrafficCar.new()
	plain.kind = "n1_commuter"
	plain.position = Vector3(5.0, 0.6, 0.0)
	root.add_child(plain)
	await process_frame
	_check(plain.get_node_or_null(CarDetail.NODE_NAME) == null, "a traffic car gets no CarDetail node")
	var cop := TrafficCar.new()
	cop.kind = "c1_patrol"
	cop.spec = CarSpec.clone_spec(CarSpec.npc_spec("c1_patrol"))
	cop.spec["parts"] = "full"
	cop.position = Vector3(-5.0, 0.6, 0.0)
	root.add_child(cop)
	await process_frame
	var d := cop.get_node_or_null(CarDetail.NODE_NAME) as CarDetail
	_check(d != null, "a cop gets a CarDetail node (underside and parts)")
	_check(cop.get_node_or_null("Calipers") != null and cop.get_node_or_null("Shocks") == null, "the cop has calipers but no shocks while driving")
	if d != null:
		d.force = true
		d.refresh()
		var sh := cop.get_node_or_null("Shocks") as MultiMeshInstance3D
		_check(sh != null and sh.visible and is_equal_approx(sh.visibility_range_end, CarParts.LOD_RANGE), "detail on builds the cop's shocks with the %.0f m range" % CarParts.LOD_RANGE)
	plain.queue_free()
	cop.queue_free()
	await process_frame
