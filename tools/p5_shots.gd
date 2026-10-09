extends SceneTree

# Review shots of the player's P5 muscle hardtop (better-cars section 1,
# 2026-10-09), not a pass/fail test: the car parked in the game's night street
# under a sodium lamp, the same views under a review "sun" for a daytime read,
# from straight below with a light from under the road, and the cockpit view.
# Also prints whether the cockpit frame (door mirrors excepted) sits inside
# the body's box.
#
# The street's sodium lamps are fake pools on the road (road_chunk_builder.gd,
# POOL_*): no light from them lands on a car, which at night is lit by the
# dim moon only. The "night" set therefore adds one sodium-coloured OmniLight3D
# where a lamp head would be (7.5 m up, 1.9 m in from the curb, 6 m ahead), a
# stand-in for what a real lamp would do to the paint. Say so when reading them.
# Writes PNGs to -- --out=<dir> (default user://p5_shots). Needs a real renderer:
#   godot --audio-driver Dummy --path . -s res://tools/p5_shots.gd -- --out=C:/tmp/p5 [--kind=p5_muscle]

func _initialize() -> void:
	var out := "user://p5_shots"
	var kind := "p5_muscle"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--kind="):
			kind = a.trim_prefix("--kind=")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CAR", kind)
	OS.set_environment("NEON_CLOCK", "23:30")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 90:
		await process_frame
	var player: Node3D = game.get("player")
	var origin: Vector3 = player.global_position
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.fov = 55.0
	cam.current = true
	# Night: the dim moon plus the sodium stand-in lamp described above.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#FF8A1F")
	lamp.light_energy = 4.0
	lamp.omni_range = 18.0
	lamp.omni_attenuation = 1.2
	lamp.position = origin + Vector3(3.2, 7.4, -6.0)
	game.add_child(lamp)
	var views := [
		["front34", Vector3(3.6, 1.4, -5.4), Vector3(0.0, 0.6, 0.0)],
		["rear34", Vector3(-3.6, 1.5, 5.2), Vector3(0.0, 0.6, 0.0)],
		["side", Vector3(6.4, 1.0, -0.2), Vector3(0.0, 0.55, 0.0)],
		["front", Vector3(0.0, 1.1, -6.5), Vector3(0.0, 0.55, 0.0)],
		["rear", Vector3(0.0, 1.1, 6.5), Vector3(0.0, 0.55, 0.0)],
	]
	await _shoot(cam, origin, views, out, "night")
	lamp.queue_free()
	# Day: a warm sun from high front-left, plus a fill so the shadow side reads.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	game.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.6
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
	game.add_child(fill)
	await _shoot(cam, origin, views, out, "day")
	sun.queue_free()
	fill.queue_free()
	# Below: the street is lit from above, so an upward review light.
	var under := DirectionalLight3D.new()
	under.light_energy = 3.0
	under.rotation_degrees = Vector3(55.0, 20.0, 0.0)
	game.add_child(under)
	await _shoot(cam, origin, [
		["below", Vector3(0.0, -3.2, 0.1), Vector3(0.0, 0.4, 0.1)],
		["low_rear", Vector3(2.4, -0.35, 3.6), Vector3(0.0, 0.3, 0.3)],
	], out, "under")
	under.queue_free()
	# Cockpit: the game's own camera in its cockpit view.
	cam.current = false
	var chase: ChaseCamera = game.get("camera")
	chase.set_view(ChaseCamera.View.COCKPIT)
	chase.make_current()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(out, "interior_cockpit")
	# Is the cockpit frame inside the body shell? Compare world-space boxes.
	var body_box := _aabb_of(player, "NpcBody")
	var frame_box := AABB()
	var mirror_box := AABB()
	for f in root.find_children("*", "CockpitFrame", true, false):
		for mi in f.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var box: AABB = (mi as MeshInstance3D).global_transform * mi.mesh.get_aabb()
			if "Mirrors" in str(f.get_path_to(mi)):
				mirror_box = _merge(mirror_box, box)
			else:
				frame_box = _merge(frame_box, box)
	print("p5_shots: door mirror box (outside the shell by design) ", mirror_box)
	print("p5_shots: body box ", body_box, " cockpit frame box ", frame_box)
	if frame_box.size != Vector3.ZERO:
		var inside := body_box.encloses(frame_box)
		print("p5_shots: cockpit inside body box: ", inside,
			"  overshoot x %.3f y %.3f z %.3f" % [
				maxf(0.0, (frame_box.end.x - body_box.end.x)), maxf(0.0, frame_box.end.y - body_box.end.y),
				maxf(0.0, maxf(body_box.position.z - frame_box.position.z, frame_box.end.z - body_box.end.z))])
	quit(0)

func _shoot(cam: Camera3D, origin: Vector3, views: Array, out: String, prefix: String) -> void:
	for v in views:
		var eye: Vector3 = origin + v[1]
		var at: Vector3 = origin + v[2]
		cam.global_position = eye
		cam.look_at(at, Vector3.UP if absf((at - eye).normalized().y) < 0.95 else Vector3.FORWARD)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		_save(out, "%s_%s" % [prefix, v[0]])

func _save(out: String, name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out, name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))

## World box of every MeshInstance3D under `node` (only under a child named
## `under_name` when given), from the meshes' own boxes.
func _aabb_of(node: Node, under_name: String) -> AABB:
	var start: Node = node
	if under_name != "":
		start = node.find_child(under_name, true, false)
		if start == null:
			return AABB()
	var box := AABB()
	for mi in start.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		box = _merge(box, (mi as MeshInstance3D).global_transform * mi.mesh.get_aabb())
	if start is MeshInstance3D and start.mesh != null:
		box = _merge(box, start.global_transform * start.mesh.get_aabb())
	return box

func _merge(a: AABB, b: AABB) -> AABB:
	if a.size == Vector3.ZERO:
		return b
	if b.size == Vector3.ZERO:
		return a
	return a.merge(b)
