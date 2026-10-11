extends SceneTree

# Renders the driver's right hand on the gear lever through a manual shift,
# for judging the shift animation by eye: the lever's travel along the gate,
# the hand on the knob and whether it clips through it. One run drives the
# coupe in MANUAL, shifts 1 -> 2 -> 3 and then 3 -> 2, and catches a frame
# every SHOT_SECS through each shift, plus the settled pose in every gear.
# Two views per frame: the game's cockpit eye pitched down at the console,
# and across the cabin from the passenger seat looking at the knob. Needs
# the real renderer (no --headless). Writes PNGs to user://shifter_shots/<tag>/,
# tag from NEON_SHOT_TAG (default "run"). The tree is paused while each frame
# is rendered, so the shots are SHOT_TICKS apart in game time.
#
#   <godot> --path . -s res://tools/shifter_shots.gd

const SHOT_TICKS := 2        # physics ticks between frames caught mid-shift
const SHOTS_PER_SHIFT := 10

var game: Node
var throttle := 0.0
var clutch := 1.0

func _initialize() -> void:
	AudioSettings.path = "user://shifter_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = throttle
		c.brake_input = 0.0
		c.steering_input = 0.0
		c.clutch_input = clutch
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
	for i in 60:
		await physics_frame
	var tag := OS.get_environment("NEON_SHOT_TAG")
	if tag == "":
		tag = "run"
	var dir := ProjectSettings.globalize_path("user://shifter_shots/" + tag)
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := Camera3D.new()
	shot.fov = 50.0
	shot.near = 0.03
	root.add_child(shot)
	throttle = 0.4
	for i in 90:
		await physics_frame
	await _shoot(shot, cam, p, frame, d, dir, "gear%d_settled" % p.gear)
	for target in [2, 3, 2]:
		var before := p.gear
		p.shift(target - before)
		for i in SHOTS_PER_SHIFT:
			for j in SHOT_TICKS:
				await physics_frame
			await _shoot(shot, cam, p, frame, d, dir, "shift_%dto%d_%02d" % [before, target, i])
		for i in 60:
			await physics_frame
		await _shoot(shot, cam, p, frame, d, dir, "gear%d_settled" % p.gear)
	print("wrote ", dir)
	quit(0)

func _shoot(shot: Camera3D, cam: ChaseCamera, p: PlayerCar, frame: CockpitFrame, d: DriverModel, dir: String, mark: String) -> void:
	paused = true
	var xf: Transform3D = p.global_transform
	var knob: Vector3 = frame.lever_knob.global_position
	# the cockpit eye pitched down at the console, as the player would glance
	shot.fov = cam.fov
	shot.global_transform = cam.global_transform
	shot.look_at(knob)
	shot.make_current()
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_eye.png" % [dir, mark])
	# across the cabin from the passenger seat, close on the knob
	shot.fov = 40.0
	shot.global_position = xf * Vector3(0.45, 0.95, 0.30)
	shot.look_at(knob)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_across.png" % [dir, mark])
	var hand := d.hand_position(1)
	var knob_car: Vector3 = frame.lever.transform * frame.lever_knob.position
	print("%s: gear %d req %d shifting %s lever %s moving %s hand-knob %.3f m" % [mark, p.gear, p.requested_gear, p.is_shifting,
			frame.lever.rotation_degrees, frame.lever_moving, hand.distance_to(knob_car)])
	paused = false
