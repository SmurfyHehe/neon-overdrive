extends SceneTree

# Renders the median barriers (RoadBarriers, R1) in the game's night scene,
# for judging them by eye: each type along the road from the driver's
# height, and a crossover with its crash cushions from above. Needs the real
# renderer (no --headless). Writes PNGs to user://barrier_shots/, or to the
# folder given after --.
#
#   <godot> --path . -s res://tools/barrier_shots.gd [-- C:/some/folder]

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _rebuild(kind: String, gap_chunk: int) -> void:
	RoadBarriers.force_kind = kind
	game.section_cache.clear()
	for c in game.chunk_pool:
		var cfg: Dictionary = game._section_at(c.index).duplicate()
		cfg.gap = c.index == gap_chunk
		game.section_cache[str(c.index)] = cfg
		RoadChunkBuilder.rebuild_chunk(c.root, c.index, game._section_at(c.index - 1), cfg, game.origin_index)

func _run() -> void:
	for i in 30:
		await process_frame
	var dir := "user://barrier_shots"
	for a in OS.get_cmdline_user_args():
		dir = a
	DirAccess.make_dir_recursive_absolute(dir)
	var p: PlayerCar = game.get("player")
	p.freeze = true
	p.visible = false
	var car_chunk := int(floor(-p.global_position.z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)
	var gap := car_chunk + 2
	var gap_root: Node3D
	for c in game.chunk_pool:
		if c.index == gap:
			gap_root = c.root
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()
	var seg := RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS
	var gap_mid := gap_root.to_global(Vector3(0.0, 0.0, -seg * float(RoadBarriers.GAP_FROM + RoadBarriers.GAP_TO + 1) / 2.0))
	for kind in [RoadBarriers.CONCRETE, RoadBarriers.GUARDRAIL, RoadBarriers.CABLE]:
		_rebuild(kind, gap)
		var views := {
			# driver's eye in lane 0, looking up the road past the barrier
			"road": [Vector3(2.0, 1.2, gap_mid.z + 45.0), Vector3(0.0, 0.6, gap_mid.z + 5.0)],
			# close, from the shoulder of the median
			"close": [Vector3(1.6, 1.0, gap_mid.z + 26.0), Vector3(0.0, 0.5, gap_mid.z + 18.0)],
			# the crossover and its cushions from above
			"gap": [Vector3(10.0, 9.0, gap_mid.z + 22.0), gap_mid + Vector3(0.0, 0.0, -2.0)],
		}
		for v in views:
			cam.global_position = views[v][0]
			cam.look_at(views[v][1], Vector3.UP)
			for i in 6:
				await process_frame
			var path := "%s/%s_%s.png" % [dir, kind, v]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("wrote ", ProjectSettings.globalize_path(path))
	quit()
