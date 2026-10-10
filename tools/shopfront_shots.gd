extends SceneTree

# World step 3 (2026-10-10): screenshots of the shop fronts for judging them
# by eye. Boots the game's night scene with no traffic, hides its own chunks,
# and for each district builds ten chunks of that district's first run on a
# straight flat road, then shoots them at three times of night from the
# chase camera's street-level pose and from the kerb, close on the fronts.
# Needs the real renderer (no --headless). Writes PNGs to
# user://shopfront_shots/<tag>/<district>_<view>_<HHMM>.png.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/shopfront_shots.gd [-- <tag> [once]]
#
# `once` shoots only the first time (for a "before" checkout, where nothing
# changes with the clock).

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const RUN := 16
## Game minutes since 8 p.m.: 8:30 (all open), 11:30 (laundromats shut),
## 2:45 (bars shut, 24-hour stores still lit).
const TIMES := [30.0, 210.0, 405.0]

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var tag := "shots"
	var once := false
	for a in OS.get_cmdline_user_args():
		if a == "once":
			once = true
		else:
			tag = a
	var dir := "user://shopfront_shots/%s" % tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for c in game.get("chunk_pool"):
		(c.root as Node3D).visible = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	var player: Node3D = game.get("player")
	if player != null:
		player.visible = false
		if player is RigidBody3D:
			(player as RigidBody3D).freeze = true
	# pin the clock (no save on exit) and drive it by hand
	var clock: Node = game.get("night_clock")
	clock.set("fixed_minutes", 0.0)
	clock.set("speed", 0.0)
	var D := B.Districts
	var runs := {}
	for r in 60:
		var n: String = D.name_of_run(r)
		if not runs.has(n):
			runs[n] = r
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	# chunk `origin` spans z 0 .. -50. street: the chase camera's rest pose
	# behind a car in the right lane (ChaseCamera DIST / HEIGHT / LOOK_*,
	# FOV_REST). kerb: stopped at the kerb beside the first shop ahead on the
	# player's side, looking across at its front (set per district below).
	var views := {
		"street": [Vector3(1.8, 1.85, 5.2), Vector3(1.8, 0.95, -12.0), 58.0],
		"kerb": [Vector3(4.0, 1.6, -5.0), Vector3(14.0, 1.9, -14.0), 58.0],
	}
	var times: Array = TIMES.slice(0, 1) if once else TIMES
	for n in runs:
		var r: int = runs[n]
		var first := r * RUN + 2
		var origin := first + 4
		var roots := []
		for idx in range(first, first + 10):
			var chunk := B.build_chunk(idx, game._section_at(idx - 1), game._section_at(idx), origin)
			game.add_child(chunk)
			roots.append(chunk)
		await process_frame
		var shop := _first_shop(roots)
		if shop != null:
			var cz := shop.global_position.z
			var fx := shop.global_position.x - shop.scale.x * 0.5
			views["kerb"] = [Vector3(4.0, 1.6, cz + 9.0), Vector3(fx, 1.9, cz), 58.0]
		for m in times:
			clock.set("minutes", m)
			WindowLights.set_minutes(m)
			var hhmm := "%02d%02d" % [NightClock.hour24(m), int(m) % 60]
			for v in views:
				cam.fov = views[v][2]
				cam.global_position = views[v][0]
				cam.look_at(views[v][1])
				for i in 12:
					await process_frame
				var path := "%s/%s_%s_%s.png" % [dir, n, v, hhmm]
				root.get_viewport().get_texture().get_image().save_png(path)
				print("wrote ", ProjectSettings.globalize_path(path))
		for chunk in roots:
			chunk.queue_free()
		await process_frame
	quit(0)

## The nearest shop, gas station or diner ahead on the player's side (x > 0,
## z < -8), or null.
func _first_shop(roots: Array) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for chunk in roots:
		for i in B._building_slots() * 2:
			var mi := chunk.get_node_or_null(NodePath("BuildingMesh%d" % i)) as MeshInstance3D
			if mi == null or not mi.visible:
				continue
			var type: String = mi.get_meta("building_type", "")
			if type != "shop" and type != "gas" and type != "diner":
				continue
			var p := mi.global_position
			if p.x < 0.0 or p.z > -8.0:
				continue
			# a front that changes with the clock beats a vacant or shuttered
			# unit (a checkout from before this step has no shop_front meta)
			var live := _live(mi)
			if best == null or (live and not _live(best)) or (live == _live(best) and p.z > best.global_position.z):
				best = mi
	return best

func _live(mi: MeshInstance3D) -> bool:
	var k: String = mi.get_meta("shop_front", "")
	return k == "store" or k == "laundromat" or k == "bar"
