extends SceneTree

# Vehicle registry checks, for every car and every look in VehicleRegistry:
#   - the model loads and all four wheel nodes are found
#   - the model faces forward (-Z) with left wheels at -X, and sits on the ground
#   - each wheel visual is centred on its own axle and has the physics radius
#   - a spawned PlayerCar puts its physics wheels at the hardpoints
#   - every credited car has a licence and source and is named in CREDITS.md
#
# Run (headless is fine; a fresh worktree needs --import once first):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/vehicle_registry.gd

const EPS := 1e-3
var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _initialize() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	for id in VehicleRegistry.PLAYER_CARS:
		if not VehicleRegistry.VEHICLES.has(id):
			_fail("PLAYER_CARS lists unknown car %s" % id)
	for id in VehicleRegistry.VEHICLES:
		var e := VehicleRegistry.entry(id)
		if VehicleRegistry.look_names(id)[0] != "stock":
			_fail("%s: first look must be stock" % id)
		if e.credit != "":
			if e.get("licence", "") == "" or e.get("source", "") == "":
				_fail("%s: credit without licence or source" % id)
			if not credits.contains(e.credit):
				_fail("%s: CREDITS.md does not name '%s'" % [id, e.credit])
		for look in VehicleRegistry.look_names(id):
			await _check_look(id, look)
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _check_look(id: String, look: String) -> void:
	var tag := "%s/%s" % [id, look]
	var car := VehicleModel.build(id, look)
	if car.is_empty():
		_fail("%s: build failed" % tag)
		return
	var hard: Dictionary = car.hardpoints
	if not (hard.front_z < 0.0 and hard.rear_z > 0.0 and hard.wheel_x > 0.0 and hard.wheel_r > 0.0):
		_fail("%s: odd hardpoints %s" % [tag, hard])

	if car.has("model_wheels"):
		var mw: Dictionary = car.model_wheels
		if not (mw.FL.x < 0.0 and mw.RL.x < 0.0 and mw.FR.x > 0.0 and mw.RR.x > 0.0):
			_fail("%s: left wheels are not at -X: %s" % [tag, mw])
		if not (mw.FL.z < mw.RL.z and mw.FR.z < mw.RR.z):
			_fail("%s: front wheels are not ahead (-Z) of the rear: %s" % [tag, mw])
		for key in mw:
			if absf(mw[key].y - car.model_wheel_r) > EPS:
				_fail("%s: %s wheel centre at y %.3f, want radius %.3f (on the ground)" % [tag, key, mw[key].y, car.model_wheel_r])

	for key in car.wheels:
		var pivot: Node3D = car.wheels[key]
		var box := VehicleModel._aabb(pivot, pivot.transform)
		if box.get_center().length() > EPS:
			_fail("%s: %s wheel visual is off its axle by %s" % [tag, key, box.get_center()])
		if absf(box.size.y * 0.5 - hard.wheel_r) > EPS:
			_fail("%s: %s wheel visual radius %.3f, physics %.3f" % [tag, key, box.size.y * 0.5, hard.wheel_r])
		pivot.free()
	car.body.free()

	PlayerCar.vehicle_id = id
	PlayerCar.look = look
	var player: PlayerCar = load("res://scripts/player.gd").new()
	root.add_child(player)
	await process_frame
	var want := {
		"FL": Vector2(-hard.wheel_x, hard.front_z), "FR": Vector2(hard.wheel_x, hard.front_z),
		"RL": Vector2(-hard.wheel_x, hard.rear_z), "RR": Vector2(hard.wheel_x, hard.rear_z),
	}
	var got := {
		"FL": player.front_left_wheel, "FR": player.front_right_wheel,
		"RL": player.rear_left_wheel, "RR": player.rear_right_wheel,
	}
	for key in want:
		var w: Wheel = got[key]
		if Vector2(w.position.x, w.position.z).distance_to(want[key]) > EPS:
			_fail("%s: player %s wheel at %s, want x/z %s" % [tag, key, w.position, want[key]])
		if absf(w.tire_radius - hard.wheel_r) > EPS:
			_fail("%s: player %s tyre radius %.3f, want %.3f" % [tag, key, w.tire_radius, hard.wheel_r])
	print("%s: wheelbase %.2f m, track %.2f m, tyre r %.2f m, body %s" % [tag, hard.rear_z - hard.front_z, hard.wheel_x * 2.0, hard.wheel_r, VehicleModel._aabb(player.chassis_visual, Transform3D()).size])
	player.free()
