extends SceneTree

# Renders street life step 2 for judging it by eye: parked cars at the kerb
# (one on alarm, dome light, hazards), bin night, a security floodlight
# caught on, dead sign letters and the dead-hour sprinklers. Districts are
# forced so each feature is in frame; the clock is set into the sprinkler
# window. Needs the real renderer (no --headless). Writes PNGs to
# user://street_life2_shots/, or to the folder given after --.
#
#   <godot> --path . -s res://tools/street_life2_shots.gd [-- C:/some/folder]

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")
const FloodLights := preload("res://scripts/world/flood_lights.gd")
const Sprinklers := preload("res://scripts/world/sprinklers.gd")

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
	var dir := "user://street_life2_shots"
	for a in OS.get_cmdline_user_args():
		dir = a
	DirAccess.make_dir_recursive_absolute(dir)
	var p: PlayerCar = game.get("player")
	p.freeze = true
	p.visible = false
	var car_z: float = p.global_position.z
	for n in game.get_children():
		if n is CanvasLayer or n is Control:
			(n as Node).set("visible", false)
	var car_chunk := int(floor(-car_z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)
	var road: float = RoadChunkBuilder._lane_w(int(game._section_at(car_chunk).own_lanes))
	var lane_x := road - RoadChunkBuilder.LANE_W * 0.5
	var kerb_x := road + RoadChunkBuilder.SHOULDER_W + RoadChunkBuilder.CURB_W
	var walk_x := kerb_x + RoadChunkBuilder.SIDEWALK_W
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()
	# the dead hours: game.gd feeds the night clock to the sprinklers each frame
	game.night_clock.set_time((Sprinklers.WINDOW.x + Sprinklers.WINDOW.y) / 2.0, 1)
	var sets := {
		"old_town_cars": ["old_town", {}, false],
		"residential_bin_night": ["residential", {}, true],
		"industrial_floods": ["industrial", {}, false],
		"strip_signs": ["strip", {}, false],
	}
	for name in sets:
		RoadsideKit.bin_night = bool(sets[name][2])
		_rebuild(String(sets[name][0]), sets[name][1])
		for i in 4:
			await process_frame
		# floodlights: hold them all on for the shot
		for c in game.chunk_pool:
			if c.root.has_meta("floods"):
				for f in c.root.get_meta("floods"):
					FloodLights._write(c.root, int(f.i), 1.0)
		var views := {
			"road": [Vector3(lane_x, 1.2, car_z - 10.0), Vector3(kerb_x, 0.6, car_z - 70.0)],
			"kerb": [Vector3(walk_x - 0.4, 1.0, car_z - 30.0), Vector3(kerb_x + 0.6, 0.5, car_z - 60.0)],
			"high": [Vector3(kerb_x - 1.0, 6.0, car_z - 5.0), Vector3(road - 2.0, 0.0, car_z - 60.0)],
		}
		# close-ups: the nearest feature of each kind in the pool, from the road
		var seen := {}
		for c in game.chunk_pool:
			var g: Transform3D = c.root.global_transform
			for f in c.root.get_meta("floods", []):
				if not seen.has("flood"):
					seen["flood"] = g * (f.pos as Vector3)
			for sp in c.root.get_meta("sprinklers", []):
				if not seen.has("sprinkler"):
					seen["sprinkler"] = g * RoadChunkBuilder._xf(float(sp.x), 0.3, float(sp.z)).origin
			for r in c.root.get_meta("kit", []):
				if String(r.kind) == RoadsideKit.CAR and int(r.mode) != 0 and r.has("p") and not seen.has("car%d" % int(r.mode)):
					seen["car%d" % int(r.mode)] = g * (r.p as Vector3)
		for key in seen:
			var at: Vector3 = seen[key]
			var dist := 12.0 if key == "flood" else 6.0
			var toward := Vector3(-signf(at.x) * dist, 1.6, dist * 0.6)
			views[key] = [at + toward, at + Vector3(0.0, 1.0, 0.0)]
		for v in views:
			cam.global_position = views[v][0]
			cam.look_at(views[v][1], Vector3.UP)
			for i in 6:
				await process_frame
			var path := "%s/%s_%s.png" % [dir, name, v]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("wrote ", ProjectSettings.globalize_path(path))
	quit()
