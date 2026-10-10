extends SceneTree

# Renders the roadside kit (RoadsideKit) in the game's night scene for judging
# it by eye: each district from the driver's height and from the kerb, plus
# a work zone (cones and jersey barriers) and the industrial guardrail,
# forced on so they are in frame. Needs the real renderer (no --headless).
# Writes PNGs to user://roadside_kit_shots/, or to the folder given after --.
# NEON_KIT=0 renders the same views without the kit (the "before" set).
#
#   <godot> --path . -s res://tools/roadside_kit_shots.gd [-- C:/some/folder]

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _rebuild(district: String, force: Dictionary) -> void:
	Districts.force = district
	RoadsideKit.force = force
	game.section_cache.clear()
	for c in game.chunk_pool:
		RoadChunkBuilder.rebuild_chunk(c.root, c.index, game._section_at(c.index - 1), game._section_at(c.index), game.origin_index)

func _run() -> void:
	for i in 30:
		await process_frame
	var dir := "user://roadside_kit_shots"
	for a in OS.get_cmdline_user_args():
		dir = a
	DirAccess.make_dir_recursive_absolute(dir)
	var p: PlayerCar = game.get("player")
	p.freeze = true
	p.visible = false
	var car_z: float = p.global_position.z
	# the HUD and debug text would sit over every shot
	for n in game.get_children():
		if n is CanvasLayer or n is Control:
			(n as Node).set("visible", false)
	# camera x from the real lane count at the car: outer lane, kerb, sidewalk
	var car_chunk := int(floor(-car_z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)
	var road: float = RoadChunkBuilder._lane_w(int(game._section_at(car_chunk).own_lanes))
	var lane_x := road - RoadChunkBuilder.LANE_W * 0.5
	var kerb_x := road + RoadChunkBuilder.SHOULDER_W + RoadChunkBuilder.CURB_W
	var walk_x := kerb_x + RoadChunkBuilder.SIDEWALK_W
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()
	var off := OS.get_environment("NEON_KIT") == "0"
	var sets := {
		"downtown": {}, "residential": {}, "strip": {}, "industrial": {},
		"workzone": {"workzone": 1.0}, "rail": {"rail": 1.0},
	}
	for name in sets:
		var district: String = "industrial" if name == "rail" else ("strip" if name == "workzone" else String(name))
		_rebuild(district, sets[name])
		for i in 4:
			await process_frame
		var views := {
			# driver's eye in the outer lane, looking up the road along the kerb
			"road": [Vector3(lane_x, 1.2, car_z - 10.0), Vector3(kerb_x, 0.6, car_z - 70.0)],
			# from the sidewalk, low, looking along the kerb
			"kerb": [Vector3(walk_x - 0.4, 1.0, car_z - 30.0), Vector3(kerb_x + 0.6, 0.5, car_z - 60.0)],
			# above the shoulder, looking down the road
			"high": [Vector3(kerb_x - 1.0, 6.0, car_z - 5.0), Vector3(road - 2.0, 0.0, car_z - 60.0)],
		}
		for v in views:
			cam.global_position = views[v][0]
			cam.look_at(views[v][1], Vector3.UP)
			for i in 6:
				await process_frame
			var path := "%s/%s_%s%s.png" % [dir, name, v, "_before" if off else ""]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("wrote ", ProjectSettings.globalize_path(path))
	quit()
