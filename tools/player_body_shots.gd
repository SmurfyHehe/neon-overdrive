extends SceneTree

# Renders the player's body (PersonKit, 2026-10-09) for judging by eye:
#   1. the design sheet: every option of every row as a standing figure in a
#      line, front and three-quarter (sheet_<row>_front.png, _quarter.png)
#   2. in the car, chase view: through the driver's window, through the
#      windscreen, and from the passenger seat (car_*.png)
#   3. in the car, cockpit view: the game's own eye with the sleeves on the
#      wheel at rest, a quarter turn and lock (eye_*.png), then pitched down
#      at the knees, and the driver alone from the passenger side (nothing
#      of the car drawn): foot off, throttle pressed, brake pressed (feet_*.png)
#   4. the seated driver alone, side and three-quarter (xray_*.png)
# Needs the real renderer (no --headless). Writes PNGs to user://player_body_shots/.
# NEON_LOOK can name the look for the car shots as row=opt pairs, e.g.
# NEON_LOOK="jacket=denim,hair=crop_fair,body=heavy,trinket=watch".
#
#   <godot> --path . -s res://tools/player_body_shots.gd

var game: Node
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var dir: String

func _initialize() -> void:
	AudioSettings.path = "user://player_body_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	dir = ProjectSettings.globalize_path("user://player_body_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var look := {}
	for pair in OS.get_environment("NEON_LOOK").split(",", false):
		var kv := pair.split("=")
		if kv.size() == 2:
			look[kv[0].strip_edges()] = kv[1].strip_edges()
	DriverModel.player_look = look
	_run.call_deferred()

func _run() -> void:
	await _sheet()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	# the brake pedal holds the car (so the hands stay on the wheel: a pulled
	# handbrake would take the right hand to the lever)
	brake = 1.0
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = throttle
		c.brake_input = brake
		c.handbrake_input = 0.0
		c.steering_input = steer
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.CHASE)
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false   # no HUD over the shots
	for i in 90:
		await physics_frame
	var shot := Camera3D.new()
	shot.fov = 50.0
	shot.near = 0.03
	root.add_child(shot)
	var xf: Transform3D = p.global_transform
	# a shot-only fill light in the cabin, so the body reads (the game's own
	# cabin light is dim by design)
	var fill := OmniLight3D.new()
	fill.light_color = Color("#FFC066")
	fill.light_energy = 3.0
	fill.omni_range = 2.5
	fill.light_cull_mask = CockpitFrame.DRIVER_BIT | CockpitFrame.INTERIOR_BIT
	fill.position = xf * Vector3(0.3, 0.95, -0.25)
	root.add_child(fill)
	var key := OmniLight3D.new()   # from the driver's side, for the driver-only shots
	key.light_color = Color("#FFC066")
	key.light_energy = 2.0
	key.omni_range = 4.0
	key.light_cull_mask = CockpitFrame.DRIVER_BIT
	key.position = xf * Vector3(CockpitFrame.SEAT_X - 1.4, 1.3, -0.6)
	root.add_child(key)
	var seat := xf * Vector3(CockpitFrame.SEAT_X, 0.95, 0.25)
	# chase view: the whole driver through the glass
	await _shoot(shot, xf * Vector3(-1.9, 1.3, -0.5), seat, "car_window")
	await _shoot(shot, xf * Vector3(-0.9, 1.5, -3.0), seat, "car_windscreen")
	await _shoot(shot, xf * Vector3(0.55, 1.12, 0.35), xf * Vector3(CockpitFrame.SEAT_X, 0.80, -0.15), "car_passenger")
	# the legs from between the seats
	shot.fov = 65.0
	await _shoot(shot, xf * Vector3(0.05, 0.95, 0.70), xf * Vector3(CockpitFrame.SEAT_X - 0.05, 0.42, -0.45), "car_legs")
	# the seated driver alone, nothing of the car drawn: side and three-quarter
	shot.fov = 45.0
	shot.cull_mask = CockpitFrame.DRIVER_BIT
	await _shoot(shot, xf * Vector3(CockpitFrame.SEAT_X - 2.4, 0.85, -0.1), xf * Vector3(CockpitFrame.SEAT_X, 0.72, -0.05), "xray_side")
	await _shoot(shot, xf * Vector3(CockpitFrame.SEAT_X - 1.7, 1.1, -1.8), xf * Vector3(CockpitFrame.SEAT_X, 0.72, -0.05), "xray_quarter")
	shot.cull_mask = 0xFFFFF
	# cockpit view, the game's own eye: the sleeves on the wheel at rest, a
	# quarter turn and full lock (the road band must stay clear)
	cam.set_view(ChaseCamera.View.COCKPIT)
	for mark in [["eye_rest", 0.0], ["eye_quarter", 0.4], ["eye_lock", 1.0]]:
		steer = mark[1]
		for i in 150:
			await physics_frame
		shot.fov = cam.fov
		shot.global_transform = cam.global_transform
		shot.make_current()
		for i in 6:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, mark[0]])
	steer = 0.0
	for i in 90:
		await physics_frame
	# cockpit view: the eye pitched down at the knees, then under the dash at
	# the shoes and pedals; foot off, throttle, brake (the car rolls a little)
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in 30:
		await physics_frame
	for mark in [["feet_rest", 0.0, 0.0], ["feet_throttle", 1.0, 0.0], ["feet_brake", 0.0, 1.0]]:
		throttle = mark[1]
		brake = mark[2]
		for i in 45:
			await physics_frame
		xf = p.global_transform
		shot.fov = 70.0
		shot.global_transform = cam.global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-58.0)), Vector3.ZERO)
		shot.make_current()
		for i in 6:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, mark[0]])
		# and the driver alone (no cabin drawn) from the passenger side, low
		shot.fov = 60.0
		shot.cull_mask = CockpitFrame.DRIVER_BIT
		await _shoot(shot, xf * Vector3(0.9, 0.55, -0.35), xf * Vector3(CockpitFrame.SEAT_X, 0.42, -0.30), mark[0] + "_xray")
		shot.cull_mask = 0xFFFFF
	throttle = 0.0
	brake = 0.0
	print("wrote ", dir)
	quit(0)

func _shoot(shot: Camera3D, from: Vector3, at: Vector3, mark: String) -> void:
	shot.look_at_from_position(from, at)
	shot.make_current()
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, mark])

## The design sheet: a line of standing figures per row, lit like the cabin.
func _sheet() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0E1424")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#1B2A4A")
	e.ambient_light_energy = 2.0
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#FFC066")
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-40.0, 215.0, 0.0)
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#8FA3C8")
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-20.0, 60.0, 0.0)
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#141821")
	floor_mesh.material_override = fm
	stage.add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.fov = 40.0
	stage.add_child(cam)
	var mat := CockpitKit.material(0.9, 0.0, 0.05)
	for row in PersonKit.ROWS:
		var opts := PersonKit.options(row)
		var figs := Node3D.new()
		stage.add_child(figs)
		var spacing := 0.75
		for i in opts.size():
			var fig := PersonKit.standing({row: opts[i]}, mat)
			fig.position = Vector3((float(i) - (opts.size() - 1) * 0.5) * spacing, 0.0, 0.0)
			figs.add_child(fig)
			var label := Label3D.new()
			label.text = String(opts[i])
			label.font_size = 48
			label.pixel_size = 0.002
			label.modulate = Color("#FFC066")
			label.position = fig.position + Vector3(0.0, 2.05, 0.0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			figs.add_child(label)
		var width := spacing * opts.size()
		var dist := maxf(3.6, width * 0.95)
		cam.look_at_from_position(Vector3(0.0, 1.1, -dist), Vector3(0.0, 1.0, 0.0))
		cam.make_current()
		for i in 8:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/sheet_%s_front.png" % [dir, row])
		cam.look_at_from_position(Vector3(-dist * 0.6, 1.3, -dist * 0.8), Vector3(0.0, 0.95, 0.0))
		for i in 8:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/sheet_%s_quarter.png" % [dir, row])
		figs.queue_free()
		await process_frame
	stage.queue_free()
	await process_frame
