extends SceneTree

# Chase-camera orbit shots (arrow keys outside the car), for judging by eye:
# the car at about 100 km/h on the road, chase view at 0 / 35 / 100 degrees to
# the left, then Up and Down held. Needs the real renderer (no --headless).
# NEON_CAR=<kind> picks the car; NEON_SHOT_DIR the output folder.
#
#   NEON_CAR=p0_beater <godot> --path . -s res://tools/chase_orbit_shots.gd

const CRUISE := 27.0

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://chase_orbit_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _run() -> void:
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		var err := CRUISE - c.current_speed()
		c.throttle_input = clampf(err * 0.3, 0.0, 1.0)
		c.brake_input = clampf(-err * 0.3, 0.0, 1.0)
		c.steering_input = 0.0
	cam.shake_enabled = false
	_hide_hud(root)   # no HUD text over the shots (Roy, 2026-10-11)
	cam.set_view(ChaseCamera.View.CHASE)
	var dir := OS.get_environment("NEON_SHOT_DIR")
	if dir == "":
		dir = "C:/SmurfyHehe/review-shots/look-around-1"
	DirAccess.make_dir_recursive_absolute(dir)
	var kind := PlayerCar.chassis_kind()
	for i in 1800:   # the beater needs most of a minute to reach 100 km/h
		await process_frame
		if absf(p.current_speed() - CRUISE) < 1.5 and i > 240:
			break
	for i in 90:
		await process_frame
	await _shot(dir, kind, "0_straight", cam)
	Input.action_press("look_left")
	for i in 5:
		await process_frame
	Input.action_release("look_left")
	for i in 30:
		await process_frame
	await _shot(dir, kind, "1_tap_35_left", cam)
	for i in 60:
		await process_frame
	Input.action_press("look_left")
	for i in 70:
		await process_frame
	await _shot(dir, kind, "2_hold_100_left", cam)
	Input.action_release("look_left")
	for i in 60:
		await process_frame
	Input.action_press("look_up")
	for i in 60:
		await process_frame
	await _shot(dir, kind, "3_up", cam)
	Input.action_release("look_up")
	for i in 60:
		await process_frame
	Input.action_press("look_down")
	for i in 60:
		await process_frame
	await _shot(dir, kind, "4_down", cam)
	Input.action_release("look_down")
	quit(0)

func _shot(dir: String, kind: String, tag: String, cam: ChaseCamera) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [dir, kind, tag]
	img.save_png(path)
	print("%s: orbit %.1f, lift %.2f, speed %.1f m/s" % [path, cam.orbit_yaw, cam.orbit_lift, (game.get("player") as PlayerCar).current_speed()])

## No HUD over the shots: every CanvasLayer in the tree goes dark.
func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)
