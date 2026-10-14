extends SceneTree

# One chase-camera shot on a bend beside a guardrail, for judging the orbit
# by eye: the car follows lane 0 (next to the median) at about 100 km/h on a
# bendy road with the guardrail barrier forced, waits for a real bend, holds
# Left (100 degrees) and shoots. Needs the real renderer (no --headless).
# NEON_CAR=<kind> picks the car; NEON_SHOT_DIR the output folder.
#
#   NEON_CAR=p1_coupe <godot> --path . -s res://tools/guardrail_bend_shot.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const CRUISE := 27.0
const MIN_CURVATURE := 1.0 / 1600.0   # 1/m; every bend the road rolls (300-1500 m radius)

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "1")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_ROAD_SEED", "7")
	RoadBarriers.force_kind = RoadBarriers.GUARDRAIL
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	await _frames(30)
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	Harness.move_player_to_lane(p, Harness.lane_x(0))
	p.driver = Harness.lane_driver(Harness.lane_x(0), 1.0, CRUISE)
	cam.shake_enabled = false
	_hide_hud(root)   # no HUD text over the shots (Roy, 2026-10-11)
	cam.set_view(ChaseCamera.View.CHASE)
	var dir := OS.get_environment("NEON_SHOT_DIR")
	if dir == "":
		dir = "C:/SmurfyHehe/review-shots/look-around-1"
	DirAccess.make_dir_recursive_absolute(dir)
	var kind := PlayerCar.chassis_kind()
	# up to speed, then the first bend that is still a bend 60 m on
	var on_bend := false
	for i in 7200:
		await process_frame
		if i < 240 or absf(p.current_speed() - CRUISE) > 2.0:
			continue
		var z := RoadFrame.unroll(p.global_position).z
		if absf(RoadFrame.curvature_at(z)) >= MIN_CURVATURE and absf(RoadFrame.curvature_at(z - 60.0)) >= MIN_CURVATURE:
			on_bend = true
			break
	if not on_bend:
		print("no bend found in 120 s; shooting where the car is")
	Input.action_press("look_left")
	await _frames(70)
	await RenderingServer.frame_post_draw
	var path := "%s/%s_5_bend_guardrail_100_left.png" % [dir, kind]
	root.get_texture().get_image().save_png(path)
	var z2 := RoadFrame.unroll(p.global_position).z
	print("%s: look %.1f deg, speed %.1f m/s, curvature %.4f 1/m, barrier %s" % [path, cam.look_yaw, p.current_speed(), RoadFrame.curvature_at(z2), RoadBarriers.kind_at(0)])
	Input.action_release("look_left")
	quit(0)

## No HUD over the shots: every CanvasLayer in the tree goes dark.
func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)
