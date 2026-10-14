extends SceneTree

# Hood-view shots, for judging by eye: the car at about 100 km/h on the road,
# hood view straight ahead, Left held (90 degrees), Up held, then B (the roof
# camera looking back). Needs the real renderer (no --headless).
# NEON_CAR=<kind> picks the car; NEON_SHOT_DIR the output folder.
#
#   NEON_CAR=p0_beater <godot> --path . -s res://tools/hood_view_shots.gd

const CRUISE := 27.0

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://hood_view_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

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
	cam.set_view(ChaseCamera.View.HOOD)
	var dir := OS.get_environment("NEON_SHOT_DIR")
	if dir == "":
		dir = "C:/SmurfyHehe/review-shots/look-around-1"
	DirAccess.make_dir_recursive_absolute(dir)
	var kind := PlayerCar.chassis_kind()
	for i in 600:
		await process_frame
		if absf(p.current_speed() - CRUISE) < 1.5 and i > 240:
			break
	await _frames(90)
	await _shot(dir, kind, "0_straight", cam)
	Input.action_press("look_left")
	await _frames(70)
	await _shot(dir, kind, "1_left_90", cam)
	Input.action_release("look_left")
	await _frames(60)
	Input.action_press("look_up")
	await _frames(60)
	await _shot(dir, kind, "2_up", cam)
	Input.action_release("look_up")
	await _frames(60)
	Input.action_press("look_back")
	await _frames(30)
	await _shot(dir, kind, "3_b_back", cam)
	Input.action_release("look_back")
	quit(0)

func _shot(dir: String, kind: String, tag: String, cam: ChaseCamera) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/hood_%s_%s.png" % [dir, kind, tag]
	img.save_png(path)
	print("%s: look %.1f / %.1f, speed %.1f m/s" % [path, cam.look_yaw, cam.look_pitch, (game.get("player") as PlayerCar).current_speed()])

## No HUD over the shots: every CanvasLayer in the tree goes dark.
func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)
