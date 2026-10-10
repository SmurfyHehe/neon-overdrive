extends SceneTree

# Renders the interior mods (batch 1, 2026-10-09) for judging them by eye:
# every trinket from the driver's eye (the game's cockpit camera), every shift
# knob and the stock stick against the short one from the eye turned down to
# the console, and the strut bar from above the engine bay with the body skin
# hidden (the hood does not open on main yet). Needs the real renderer (no
# --headless). Writes PNGs to user://cabin_mods_shots/.
#
#   <godot> --path . -s res://tools/cabin_mods_shots.gd

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://cabin_mods_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CABIN_MODS", "trinket=dice;knob=ball;short=1;strut=1")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _snap(path: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	for i in 60:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://cabin_mods_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	# 1. every trinket, the game's own cockpit camera
	for id in DashTrinket.IDS:
		CabinMods.set_trinket(id)
		for i in 10:
			await physics_frame
		await _snap("%s/trinket_%s_eye.png" % [dir, id])
	CabinMods.set_trinket("dice")
	# 2. the knobs and the stick, from the eye turned down to the console; the
	# knob is the manual stick's (the automatic T-handle keeps its shape)
	p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
	for i in 10:
		await physics_frame
	var shot := Camera3D.new()
	shot.fov = 62.0
	shot.near = 0.03
	root.add_child(shot)
	var xf: Transform3D = p.global_transform
	var eye := xf * cam.eye
	for short in [false, true]:
		CabinMods.set_short_shifter(short)
		for id in CabinMods.KNOB_IDS:
			CabinMods.set_shift_knob(id)
			for i in 6:
				await physics_frame
			shot.global_position = eye
			shot.look_at(xf * (CabinSpots.cabin(PlayerCar.chassis_kind(), "shifter") + PlayerCars.cabin_offset(PlayerCar.chassis_kind()) + Vector3(0.0, 0.16, 0.0)))
			shot.make_current()
			await _snap("%s/knob_%s_%s.png" % [dir, id, "short" if short else "stock"])
			print("knob %s %s: knob at y %.3f" % [id, "short" if short else "stock", frame.lever_knob.position.y])
	CabinMods.set_shift_knob("ball")
	CabinMods.set_short_shifter(true)
	# 3. the strut bar from above the bay, body skin hidden (chase view, the
	# body comes back on the car layer)
	cam.set_view(ChaseCamera.View.CHASE)
	for i in 10:
		await physics_frame
	var body := p.chassis_visual.get_node_or_null(^"Body") as VisualInstance3D
	var ends := CabinSpots.strut_bar(PlayerCar.chassis_kind())
	var mid := xf * ((ends[0] + ends[1]) * 0.5)
	shot.fov = 55.0
	shot.global_position = mid + xf.basis * Vector3(0.0, 0.9, 0.9)
	shot.look_at(mid)
	shot.make_current()
	if body != null:
		body.visible = false
	await _snap("%s/strut_bar_bay_skin_hidden.png" % dir)
	if body != null:
		body.visible = true
	await _snap("%s/strut_bar_bay_skin_on.png" % dir)
	print("wrote ", dir)
	quit(0)
