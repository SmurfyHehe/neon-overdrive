extends SceneTree

# Lamp-post life screenshots (living world step 2, 2026-10-10): the same
# night street from a driver-height chase view, before (the four effects
# hidden) and after, plus close-ups of each effect. Boots the game's night
# scene with no traffic, hides its own chunks, builds one 16-chunk district
# run per district on a straight flat road, and for each district shoots
# street / steam / moths / banner / litter. Needs the real renderer.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/lamp_life_shots.gd -- <tag>
#
# <tag> names the output folder user://lamp_life_shots/<tag>/. The street view
# is shot twice from the same chunks in the same process, first with the five
# lamp-life nodes hidden (_street_before) and then shown (_street_after), so
# the two differ only by this step. The bat and the litter gust are held at
# mid-run through LampLife.freeze_for_shots, so the shots do not depend on
# when they are taken.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const L := preload("res://scripts/world/lamp_life.gd")
const RUN := 16
const NODES := ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter"]

var game: Node
var cam: Camera3D
var dir := ""

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _shoot(name: String, pos: Vector3, aim: Vector3, fov: float, frames: int = 10) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(aim)
	for i in frames:
		await process_frame
	var path := "%s/%s.png" % [dir, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))

func _first(chunks: Array, node: String) -> Array:
	# [chunk, instance index] of the first chunk with this node showing
	for ch in chunks:
		var mm: MultiMesh = (ch.get_node(NodePath(node)) as MultiMeshInstance3D).multimesh
		if mm.visible_instance_count > 0:
			return [ch, 0]
	return []

func _run() -> void:
	for i in 30:
		await process_frame
	var tag := "shots"
	for a in OS.get_cmdline_user_args():
		tag = a
	dir = "user://lamp_life_shots/%s" % tag
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
	DisplayServer.window_set_size(Vector2i(1280, 720))
	cam = Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	L.enabled = true
	L.set_wind(L.DEFAULT_WIND)
	var D := B.Districts
	var runs := {}
	for r in 60:
		var n: String = D.name_of_run(r)
		if not runs.has(n):
			runs[n] = r
	var lane_x_default := 2.0  # the middle of the player's first lane
	for n in runs:
		var r: int = runs[n]
		var first := r * RUN
		var origin := first + 1
		var chunks := []
		seed(4242 + r)  # the buildings roll the global sequence: same street before and after
		for idx in range(first, first + RUN):
			var chunk := B.build_chunk(idx, game._section_at(idx - 1), game._section_at(idx), origin)
			game.add_child(chunk)
			chunks.append(chunk)
		for i in 3:
			await process_frame
		# litter and bat first, picked from the chunks whose gust / flight is
		# on right now (the shader clock is not ours to set): no waiting, so
		# the shot is taken within a frame or two of the prediction
		await _time_driven_shots(n, chunks, lane_x_default)
		# a chunk with a vent, one with a banner, one with a moth swarm
		var vent := _first(chunks, "SteamVents")
		var banner := _first(chunks, "LampBanners")
		var moth := _first(chunks, "LampMoths")
		if vent.is_empty() or banner.is_empty() or moth.is_empty():
			print("no vent/banner/moth in the %s run" % n)
			continue
		var vch: Node3D = vent[0]
		var vmm: MultiMesh = (vch.get_node(^"SteamVents") as MultiMeshInstance3D).multimesh
		var vp: Vector3 = vch.global_transform * vmm.get_instance_transform(0).origin
		var lane_x := 2.0  # the middle of the player's first lane
		await _street_and_steam(n, vp, lane_x, chunks)
		var bch: Node3D = banner[0]
		var bmm: MultiMesh = (bch.get_node(^"LampBanners") as MultiMeshInstance3D).multimesh
		var bxf: Transform3D = bch.global_transform * bmm.get_instance_transform(0)
		var bpos := bxf.origin + bxf.basis * Vector3(-0.26, 4.8, 0.0)
		# from the road, 5 m back along it and 3 m toward the centre
		await _shoot("%s_banner" % n, bxf.origin + bxf.basis * Vector3(-4.5, 2.4, 5.5), bpos, 55.0)
		var mch: Node3D = moth[0]
		var mmm: MultiMesh = (mch.get_node(^"LampMoths") as MultiMeshInstance3D).multimesh
		var mxf: Transform3D = mch.global_transform * mmm.get_instance_transform(0)
		var head := mxf.origin + mxf.basis * L.HEAD
		await _shoot("%s_moths" % n, head + mxf.basis * Vector3(-2.5, -3.0, 4.0), head + Vector3(0, -0.2, 0), 38.0)
		for ch in chunks:
			ch.queue_free()
		await process_frame
	quit(0)

func _set_life(chunks: Array, on: bool) -> void:
	for ch in chunks:
		for nn in NODES:
			(ch.get_node(NodePath(nn)) as Node3D).visible = on

func _street_and_steam(n: String, vp: Vector3, lane_x: float, chunks: Array) -> void:
	# the driver's chase view: low and behind, looking down the street
	var pos := Vector3(lane_x, 2.2, vp.z + 16.0)
	var aim := Vector3(0.0, 1.8, vp.z - 40.0)
	_set_life(chunks, false)
	await _shoot("%s_street_before" % n, pos, aim, 70.0)
	_set_life(chunks, true)
	await _shoot("%s_street_after" % n, pos, aim, 70.0)
	await _shoot("%s_steam" % n, Vector3(lane_x, 1.5, vp.z + 6.5), vp + Vector3(0.0, 1.0, 0.0), 60.0, 40)

func _time_driven_shots(n: String, chunks: Array, lane_x: float) -> void:
	# hold every gust and every bat mid-run, so the shot does not depend on
	# when it is taken
	L.freeze_for_shots(0.5)
	var lt := (chunks[2] as Node3D).global_transform
	await _shoot("%s_litter" % n, lt * Vector3(lane_x, 1.2, -6.0), lt * Vector3(0.0, 0.4, -27.0), 55.0, 3)
	for ch in chunks:
		var mmm: MultiMesh = (ch.get_node(^"LampMoths") as MultiMeshInstance3D).multimesh
		for k in mmm.visible_instance_count:
			if mmm.get_instance_custom_data(k).a > 0.5:
				var xf: Transform3D = (ch as Node3D).global_transform * mmm.get_instance_transform(k)
				var head := xf.origin + xf.basis * L.HEAD
				# the bat at u = 0.5 is at the middle of the pool, 4.6 m up
				var at := xf.origin + xf.basis * Vector3(L.HEAD.x + 1.6 * sin(3.0 + mmm.get_instance_custom_data(k).r * 6.28), 4.6 + 1.1 * sin(4.5 + mmm.get_instance_custom_data(k).b * 6.0), 0.0)
				await _shoot("%s_bat" % n, at + xf.basis * Vector3(-2.0, -1.0, 3.5), at, 40.0, 3)
				L.freeze_for_shots(-1.0)
				return
	L.freeze_for_shots(-1.0)
	print("no bat swarm in the %s run" % n)
