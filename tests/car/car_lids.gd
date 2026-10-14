extends SceneTree

# The hood and trunk open in the game (engine bays B1 + B2, CarLids;
# notes/engine-bays-better-2026-10-13.md section 6, roadside-hood-pop R0).
# Checks, on a player car standing on a flat floor:
# - Y tapped right after a stop does nothing (the car must stand STOP_HOLD_S);
#   tapped once it stands, the hood pops onto its catch at once and lifts to
#   the hinge's open_deg in about OPEN_TIME; the panel leaves the body as one
#   hinge node (+1 draw call), CarDetail.panel_open is set and the bay shows,
#   the hazards come on, the car sits on the handbrake
# - Y held opens the other lid (the trunk) as well: two hinge nodes
# - gas shuts every lid; once they are down the body is the one closed mesh
#   again (no hinge nodes, no extra draw call), the bay is hidden, the hazards
#   go back to how they were
# - a push over DRIVE_OFF_SPEED drops an open lid shut
# - rolling at 3 km/h, Y opens nothing
# - on the Bug (engine at the back) a tap opens the rear lid, a hold the front
# - in the game (Game.tscn), the chase camera cuts to standing at the nose
#   while the hood is up, and goes back behind the car once it is shut
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/car/car_lids.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var logger := Harness.ErrorCounter.new()
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	root.size = Vector2i(1280, 720)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Waits t seconds of physics ticks (headless draws frames faster than it ticks).
func _secs(t: float) -> void:
	var until := Engine.get_physics_frames() + int(ceil(t * float(Engine.physics_ticks_per_second)))
	while Engine.get_physics_frames() < until:
		await process_frame

static func _brake() -> Callable:
	return func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
		c.steering_input = 0.0

static func _gas() -> Callable:
	return func(c: PlayerCar) -> void:
		c.throttle_input = 1.0
		c.brake_input = 0.0
		c.handbrake_input = 0.0
		c.steering_input = 0.0

func _tap(action: String) -> void:
	Input.action_press(action)
	await _secs(0.05)
	Input.action_release(action)
	await _secs(0.05)

func _hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await _secs(secs)
	Input.action_release(action)
	await _secs(0.05)

func _run() -> void:
	_check(InputMap.has_action(CarLids.ACTION), "no %s action in the input map" % CarLids.ACTION)
	await _bare("p1_coupe")
	await _bare_bug()
	await _in_game()
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("car_lids: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

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

func _spawn(kind: String) -> PlayerCar:
	var player: PlayerCar = load("res://scripts/car/player.gd").new()
	player.chassis = kind
	player.position = Vector3(0.0, 0.6, 0.0)
	player.driver = _brake()
	root.add_child(player)
	await _secs(1.5)   # drop onto the floor and settle
	return player

func _hinge_nodes(body: MeshInstance3D) -> Array:
	return body.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("hinge_"))

func _bare(kind: String) -> void:
	var fl := _floor()
	root.add_child(fl)
	var gs := GameState.new()
	root.add_child(gs)
	CarDetail.bind_state(gs)
	var p := await _spawn(kind)
	var body := CarAssembler.body_of(p)
	var lids := CarLids.of(p)
	_check(body != null and lids != null, "%s: no parts body or no CarLids" % kind)
	if body == null or lids == null:
		return
	_check(lids.engine_lid == "hinge_hood" and lids.other_lid == "hinge_trunk", "%s: lids are %s / %s" % [kind, lids.engine_lid, lids.other_lid])
	var closed_surfaces := body.mesh.get_surface_count()
	var lamps := p.get_node("CarLamps") as CarLamps
	var detail := CarDetail.of(p)

	# just stopped: Y does nothing yet
	lids._still_t = 0.0
	await _tap(CarLids.ACTION)
	_check(not lids.any_open(), "%s: the hood opened before the car had stood %.1f s" % [kind, CarLids.STOP_HOLD_S])
	await _secs(CarLids.STOP_HOLD_S + 0.3)
	_check(lids.can_open(), "%s: standing %.1f s does not allow a lid" % [kind, CarLids.STOP_HOLD_S + 0.3])

	# tap: the hood pops onto the catch and lifts
	await _tap(CarLids.ACTION)
	_check(lids.is_open("hinge_hood"), "%s: Y tap did not open the hood" % kind)
	var a0 := lids.angle("hinge_hood")
	_check(a0 >= CarLids.CATCH_DEG, "%s: the latch did not pop the hood onto its catch (%.1f deg)" % [kind, a0])
	var nodes := _hinge_nodes(body)
	_check(nodes.size() == 1 and String(nodes[0].name) == "hinge_hood", "%s: hinge nodes after a tap: %s" % [kind, nodes])
	_check(body.mesh.get_surface_count() == closed_surfaces, "%s: the split body has %d surfaces, closed %d" % [kind, body.mesh.get_surface_count(), closed_surfaces])
	if nodes.size() == 1:
		var panel := (nodes[0] as Node).get_node_or_null("Panel") as MeshInstance3D
		_check(panel != null and panel.mesh.get_surface_count() == 1, "%s: the hood panel is not one surface" % kind)
	_check(detail.panel_open and detail.on, "%s: CarDetail does not see the open hood (panel_open %s, on %s)" % [kind, detail.panel_open, detail.on])
	var bay := body.get_node_or_null(CarAssembler.BAY_NODE_NAME)
	if CarAssembler.bay_part_names(kind).is_empty():
		_check(bay == null, "%s has no bay parts but a Bay node" % kind)
	else:
		_check(bay != null and (bay as Node3D).visible, "%s: the bay does not show under the open hood" % kind)
	_check(lamps.hazard, "%s: the hazards did not come on with the hood" % kind)
	_check(p.lid_open, "%s: the car is not held (lid_open) with the hood up" % kind)
	var open_deg := float(CarAssembler.hinges(kind)["hinge_hood"].open_deg)
	await _secs(CarLids.OPEN_TIME + 0.3)
	var a1 := lids.angle("hinge_hood")
	_check(is_equal_approx(a1, open_deg), "%s: hood at %.1f deg after %.1f s, want %.0f" % [kind, a1, CarLids.OPEN_TIME + 0.3, open_deg])
	var hinge := body.get_node("hinge_hood") as Node3D
	_check(absf(rad_to_deg(hinge.rotation.x) - open_deg) < 0.5, "%s: the hinge node is turned %.1f deg, want %.0f" % [kind, rad_to_deg(hinge.rotation.x), open_deg])

	# hold: the trunk too
	await _hold(CarLids.ACTION, CarLids.HOLD_S + 0.2)
	_check(lids.is_open("hinge_trunk") and lids.is_open("hinge_hood"), "%s: Y held did not open the trunk as well (%s)" % [kind, lids.lids.keys()])
	_check(_hinge_nodes(body).size() == 2, "%s: hinge nodes with both lids up: %d" % [kind, _hinge_nodes(body).size()])
	_check(is_equal_approx(lids.angle("hinge_hood"), open_deg), "%s: opening the trunk reset the hood to %.1f deg" % [kind, lids.angle("hinge_hood")])

	# gas shuts everything; down, the body is one closed mesh again
	p.driver = _gas()
	await _secs(0.1)
	p.driver = _brake()
	_check(not lids.any_open(), "%s: gas did not shut the lids" % kind)
	_check(not detail.panel_open, "%s: panel_open still set after gas" % kind)
	_check(not lamps.hazard, "%s: the hazards stayed on after the lids shut" % kind)
	_check(not p.lid_open, "%s: the car is still held after the lids shut" % kind)
	await _secs(CarLids.SHUT_TIME + 0.4)
	_check(_hinge_nodes(body).is_empty(), "%s: hinge nodes still on the shut car: %s" % [kind, _hinge_nodes(body)])
	_check(CarAssembler.split_hinges(body).is_empty(), "%s: the body is still split: %s" % [kind, CarAssembler.split_hinges(body)])
	_check(body.mesh == CarAssembler._merged(kind, {}).body, "%s: the shut body is not the closed mesh" % kind)
	if bay != null:
		_check(not (bay as Node3D).visible, "%s: the bay still shows with the lids shut" % kind)
	await _secs(0.5)

	# a push drops it shut
	await _secs(CarLids.STOP_HOLD_S + 0.3)
	await _tap(CarLids.ACTION)
	_check(lids.is_open("hinge_hood"), "%s: Y did not open the hood again" % kind)
	p.linear_velocity = Vector3(0.0, 0.0, -(CarLids.DRIVE_OFF_SPEED + 0.3))
	await _frames(3)
	_check(not lids.any_open(), "%s: a %.1f m/s push left the hood up" % [kind, CarLids.DRIVE_OFF_SPEED + 0.3])
	await _secs(1.0)

	# rolling at 3 km/h: nothing opens
	var until := Engine.get_physics_frames() + Engine.physics_ticks_per_second
	while Engine.get_physics_frames() < until:
		p.linear_velocity = Vector3(0.0, 0.0, -3.0 / 3.6)
		await process_frame
	Input.action_press(CarLids.ACTION)
	for i in 3:
		p.linear_velocity = Vector3(0.0, 0.0, -3.0 / 3.6)
		await process_frame
	Input.action_release(CarLids.ACTION)
	for i in 3:
		p.linear_velocity = Vector3(0.0, 0.0, -3.0 / 3.6)
		await process_frame
	_check(not lids.any_open(), "%s: the hood opened at 3 km/h" % kind)
	p.linear_velocity = Vector3.ZERO
	await _secs(CarLids.SHUT_TIME + 0.3)

	p.queue_free()
	gs.queue_free()
	fl.queue_free()
	await _frames(2)

func _bare_bug() -> void:
	var fl := _floor()
	root.add_child(fl)
	var p := await _spawn("p0_beater")
	var lids := CarLids.of(p)
	_check(lids != null and lids.engine_lid == "hinge_trunk" and lids.other_lid == "hinge_hood", "the Bug's lids: %s / %s" % [lids.engine_lid if lids else "-", lids.other_lid if lids else "-"])
	if lids != null:
		await _secs(CarLids.STOP_HOLD_S + 0.4)
		await _tap(CarLids.ACTION)
		_check(lids.is_open("hinge_trunk") and not lids.is_open("hinge_hood"), "Bug: a tap should open the rear (engine) lid: %s" % [lids.lids.keys()])
		_check(lids.lid_end("hinge_trunk") > 0.0 and lids.lid_end("hinge_hood") < 0.0, "Bug: lid ends %.0f / %.0f" % [lids.lid_end("hinge_trunk"), lids.lid_end("hinge_hood")])
		await _hold(CarLids.ACTION, CarLids.HOLD_S + 0.2)
		_check(lids.is_open("hinge_hood"), "Bug: a hold should open the front lid")
		lids.shut_all()
		await _secs(CarLids.SHUT_TIME + 0.3)
	p.queue_free()
	fl.queue_free()
	await _frames(2)

func _in_game() -> void:
	OS.set_environment("NEON_CAR", "p1_coupe")
	var game := Harness.boot(self, 0, 150.0, 7, 1.0e6)
	await _frames(60)
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	_check(p != null and cam != null, "the game did not boot with a player and a camera")
	if p == null or cam == null:
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 0.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.CHASE)
	await _secs(1.5)
	var lids := CarLids.of(p)
	_check(lids != null and lids.can_open(), "in the game the stopped car cannot open a lid")
	if lids == null:
		return
	var half_l := float(p.chassis_visual.get_meta("half_l", 2.2))
	await _tap(CarLids.ACTION)
	_check(lids.is_open("hinge_hood"), "in the game Y did not open the hood")
	await _frames(4)
	var local := p.global_transform.affine_inverse() * cam.global_position
	_check(local.z < -half_l and local.z > -(half_l + 2.0), "the bay view does not stand at the nose (car-space z %.2f, nose %.2f)" % [local.z, -half_l])
	_check(absf(local.x) < 0.3, "the bay view is off centre (x %.2f)" % local.x)
	_check(local.y > 1.0, "the bay view is too low (y %.2f)" % local.y)
	var fwd := -cam.global_transform.basis.z
	var to_hood := (p.global_transform * lids.hinge_point("hinge_hood")) - cam.global_position
	_check(fwd.dot(to_hood.normalized()) > 0.8, "the bay view does not look at the bay")
	# shut: back behind the car
	lids.shut_all()
	await _secs(CarLids.SHUT_TIME + 0.5)
	local = p.global_transform.affine_inverse() * cam.global_position
	_check(local.z > 0.0, "after the hood shuts the chase camera is not behind the car (z %.2f)" % local.z)
	_check(cam.view == ChaseCamera.View.CHASE, "the view changed while the hood was up: %s" % cam.view)
	OS.set_environment("NEON_CAR", "")
	game.queue_free()
	await _frames(2)
