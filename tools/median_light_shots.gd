extends SceneTree

# Night screenshots of the median (the centre barrier) as the player's own
# headlights pass along it, for judging its lighting by eye. The car drives
# the fast lane on the normal bendy, hilly road; every few seconds it takes a
# set of views with the headlights on and off. Needs the real renderer (no
# --headless). Writes PNGs to user://median_light_shots/, or to the folder
# given after --.
#
#   <godot> --path . -s res://tools/median_light_shots.gd [-- C:/some/folder]

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const STOPS := 4
const MAX_SECS := 90.0
const SPEED := 30.0

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_ROAD_SEED", "7")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var dir := "user://median_light_shots"
	var burst := false
	for a in OS.get_cmdline_user_args():
		if a == "--burst":
			burst = true
		else:
			dir = a
	DirAccess.make_dir_recursive_absolute(dir)
	var p: PlayerCar = game.get("player")
	var lane := Harness.lane_x(0)
	p.driver = Harness.lane_driver(lane, 0.6, SPEED)
	if burst:
		await _burst(p, dir)
		quit()
		return
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 600.0
	root.add_child(cam)
	cam.make_current()
	var spot := p.get_node_or_null("Headlights") as SpotLight3D
	# name -> [camera offset, look-at offset], both in the car's own frame
	# (x right, y up, -z ahead). The barrier is `lane` to the car's left.
	var views := {
		"chase": [Vector3(0.0, 2.2, 6.5), Vector3(-lane * 0.5, 0.4, -25.0)],
		"low": [Vector3(-1.3, 0.9, -1.0), Vector3(-lane, 0.3, -16.0)],
		"wall": [Vector3(-1.2, 0.8, -6.0), Vector3(-lane, 0.3, -10.0)],
		"over": [Vector3(-lane, 7.0, 2.0), Vector3(-lane, 0.0, -16.0)],
		"back": [Vector3(-lane + 1.0, 1.4, -30.0), Vector3(-lane, 0.3, -12.0)],
	}
	# One stop per barrier chunk: "a" as the wall starts ahead, "b" beside it.
	var done := {}
	var t := 0.0
	while t < MAX_SECS and done.size() < STOPS * 2:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		_aim(cam, p, views["chase"])
		var s := -RoadFrame.unroll(p.global_position).z + float(game.origin_index) * RoadChunkBuilder.CHUNK_LEN
		var idx := int(floor(s / RoadChunkBuilder.CHUNK_LEN))
		var along := s - float(idx) * RoadChunkBuilder.CHUNK_LEN
		var tag := ""
		if _barrier(idx + 1) and not _barrier(idx) and along > 32.0:
			tag = "c%d_a" % (idx + 1)
		elif _barrier(idx) and along > 12.0:
			tag = "c%d_b" % idx
		if tag == "" or done.has(tag):
			continue
		done[tag] = true
		for lit in [true, false]:
			if spot != null:
				spot.visible = lit
			for v in views:
				_aim(cam, p, views[v])
				await process_frame
				_aim(cam, p, views[v])
				await process_frame
				await RenderingServer.frame_post_draw
				var path := "%s/%s_%s_%s.png" % [dir, tag, v, "on" if lit else "off"]
				root.get_viewport().get_texture().get_image().save_png(path)
		if spot != null:
			spot.visible = true
		print("%s at z=%.0f speed=%.0f" % [tag, p.global_position.z, p.current_speed()])
	print("wrote ", ProjectSettings.globalize_path(dir))
	quit()

## The game's own chase camera, every third frame past the first barrier
## chunks: for spotting flicker and pop-in, which a still cannot show.
func _burst(p: PlayerCar, dir: String) -> void:
	var n := 0
	var frame := 0
	var t := 0.0
	while t < MAX_SECS and n < 120:
		await process_frame
		t += 1.0 / maxf(Engine.get_frames_per_second(), 20.0)
		var s := -RoadFrame.unroll(p.global_position).z + float(game.origin_index) * RoadChunkBuilder.CHUNK_LEN
		var idx := int(floor(s / RoadChunkBuilder.CHUNK_LEN))
		if not (_barrier(idx) or _barrier(idx + 1) or _barrier(idx + 2)):
			continue
		frame += 1
		if frame % 3 != 0:
			continue
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/f%03d_c%d.png" % [dir, n, idx])
		n += 1
	print("wrote ", ProjectSettings.globalize_path(dir))

func _barrier(idx: int) -> bool:
	return game._section_at(idx).get("barrier", false) == true

func _aim(cam: Camera3D, p: Node3D, view: Array) -> void:
	var xf := p.global_transform
	cam.global_position = xf * (view[0] as Vector3)
	cam.look_at(xf * (view[1] as Vector3), Vector3.UP)
