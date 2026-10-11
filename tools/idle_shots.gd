extends SceneTree

# Renders the idle actions (L) for judging them by eye: the cockpit mid-puff
# with the window shut and the cloud hanging, the cockpit mid-sip, the chase
# view with the window down and the cloud trailing at speed, and one close
# view of each from outside the driver's door. Needs the real renderer (no
# --headless). Writes PNGs to screenshots/idle/ in the project folder.
# NEON_CAR picks the car.
#
#   <godot> --path . -s res://tools/idle_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var game: Node
var p: PlayerCar
var cam: ChaseCamera
var d: DriverModel
var close: Camera3D
var dir := ""
var kind := ""

func _initialize() -> void:
	AudioSettings.path = "user://idle_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _shot(view: String, label: String) -> void:
	if view == "close":
		var xf: Transform3D = p.global_transform
		close.global_position = xf * Vector3(-1.9, 1.25, -1.0)
		close.look_at(xf * Vector3(-0.5, 1.0, 0.1))
		close.make_current()
	else:
		cam.set_view(ChaseCamera.View.COCKPIT if view == "cockpit" else ChaseCamera.View.CHASE)
		cam.make_current()
	Engine.time_scale = 0.02   # hold the moment while the frame settles
	for i in 12:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [dir, kind, view, label])
	print("%s %s %s: hand at %s, %d puffs" % [kind, view, label, str(d.hold_hands[IdleActions.item].position), d.props.puff_count()])
	Engine.time_scale = 1.0

## Presses L and waits `secs` into the use.
func _use(secs: float) -> void:
	Input.action_press("idle_action")
	for i in 3:
		await physics_frame
	Input.action_release("idle_action")
	for i in int(secs * 60.0) - 3:
		await physics_frame

func _run() -> void:
	for i in 30:
		await process_frame
	p = game.get("player")
	cam = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	d = cam.frame.driver
	for i in 60:
		await physics_frame
	dir = ProjectSettings.globalize_path("res://screenshots/idle")
	DirAccess.make_dir_recursive_absolute(dir)
	kind = PlayerCar.chassis_kind()
	close = Camera3D.new()
	close.fov = 50.0
	close.near = 0.03
	root.add_child(close)

	# the vape, window shut: at the mouth, then the cloud in the cabin
	IdleActions.set_item(IdleActions.VAPE)
	cam.perspective.window = 0.0
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _use(1.1)
	await _shot("cockpit", "vape_shut_draw")
	await _shot("close", "vape_shut_draw")
	cam.set_view(ChaseCamera.View.COCKPIT)
	cam.make_current()
	for i in 45:
		await physics_frame
	await _shot("cockpit", "vape_shut_cloud")
	while d.is_idling() or d.props.puff_count() > 0:
		await physics_frame

	# the beer: mid-sip
	IdleActions.set_item(IdleActions.BEER)
	for i in 10:
		await physics_frame
	await _use(1.15)
	await _shot("cockpit", "beer_sip")
	await _shot("chase", "beer_sip")
	await _shot("close", "beer_sip")
	while d.is_idling():
		await physics_frame

	# the vape, window down, on the move: the cloud trails back along the car
	IdleActions.set_item(IdleActions.VAPE)
	cam.perspective.window = 1.0
	cam.set_view(ChaseCamera.View.CHASE)
	cam.make_current()
	p.driver = Harness.lane_driver(p.global_position.x, 0.5, 14.0)
	Harness.launch_player(p, 14.0)
	for i in 90:
		await physics_frame
	await _use(1.95)
	await _shot("chase", "vape_open_cloud")
	await _shot("close", "vape_open_cloud")
	quit(0)
