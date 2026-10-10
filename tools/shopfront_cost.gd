extends SceneTree

# World step 3 (2026-10-10): what the shop rooms cost on the GPU. Boots the
# night scene with no traffic, builds ten downtown chunks (the densest shop
# fronts at the kerb) and holds a street-level camera on them, then measures
# the viewport's GPU render time with the rooms ON and OFF, alternating every
# FRAMES frames for ROUNDS rounds in the same process, so a laptop loaded by
# other work drifts the same way for both. OFF sets every building's `room`
# instance uniform to -1, which skips the room branch; everything else in
# the frame is identical. Prints the per-round pair and the median of the
# differences. Needs the real renderer; run it at the game's resolution:
#
#   <godot> --path . --audio-driver Dummy --resolution 1920x1080 -s res://tools/shopfront_cost.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const RUN := 16
const FRAMES := 60
const ROUNDS := 10
## Game minutes since 8 p.m.: 8:30, everything open and lit (the dearest case).
const MINUTES := 30.0

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
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
	var clock: Node = game.get("night_clock")
	clock.set("fixed_minutes", MINUTES)
	clock.set("speed", 0.0)
	clock.set("minutes", MINUTES)
	WindowLights.set_minutes(MINUTES)
	var D := B.Districts
	var r := 0
	for k in 60:
		if D.name_of_run(k) == "downtown":
			r = k
			break
	var first := r * RUN + 2
	var origin := first + 4
	var meshes: Array[MeshInstance3D] = []
	for idx in range(first, first + 10):
		var chunk := B.build_chunk(idx, game._section_at(idx - 1), game._section_at(idx), origin)
		game.add_child(chunk)
		for i in B._building_slots() * 2:
			var mi := chunk.get_node_or_null(NodePath("BuildingMesh%d" % i)) as MeshInstance3D
			if mi != null:
				meshes.append(mi)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	cam.fov = 58.0
	var vp := root.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# three poses: the chase camera's rest pose in the right lane; stopped at
	# the kerb looking along the fronts; and nose to the glass of the first
	# shop so its room fills the screen (the worst case, an upper bound per
	# screen of glass)
	var poses := {
		"chase": [Vector3(1.8, 1.85, 5.2), Vector3(1.8, 0.95, -12.0)],
		"kerb": [Vector3(4.5, 1.5, 0.0), Vector3(9.0, 2.0, -40.0)],
	}
	var shop: MeshInstance3D = null
	for mi in meshes:
		if not mi.visible or int(mi.get_instance_shader_parameter("room")) < 0:
			continue
		if mi.global_position.x > 0.0 and mi.global_position.z < -8.0 and (shop == null or mi.global_position.z > shop.global_position.z):
			shop = mi
	if shop != null:
		var fx := shop.global_position.x - shop.scale.x * 0.5
		var cz := shop.global_position.z
		poses["glass"] = [Vector3(fx - 1.6, 1.7, cz), Vector3(fx, 1.7, cz)]
	var rooms: Array[int] = []
	for mi in meshes:
		var v = mi.get_instance_shader_parameter("room")
		rooms.append(int(v) if v != null else -1)
	var fronts := 0
	for v in rooms:
		fronts += 1 if v >= 0 else 0
	print("cost: %d buildings, %d with shop fronts, window %s" % [meshes.size(), fronts, str(DisplayServer.window_get_size())])
	for pose in poses:
		cam.global_position = poses[pose][0]
		cam.look_at(poses[pose][1])
		var diffs: Array[float] = []
		var ons: Array[float] = []
		var offs: Array[float] = []
		for round in ROUNDS:
			var on := await _measure(vp, meshes, rooms, true)
			var off := await _measure(vp, meshes, rooms, false)
			ons.append(on)
			offs.append(off)
			diffs.append(on - off)
			print("  %s round %d: rooms on %.3f ms, off %.3f ms, diff %+.3f ms" % [pose, round, on, off, on - off])
		diffs.sort()
		ons.sort()
		offs.sort()
		var mid := ROUNDS / 2
		print("COST %s: median gpu on %.3f ms, off %.3f ms, median diff %+.3f ms (min %+.3f, max %+.3f)" % [pose, ons[mid], offs[mid], diffs[mid], diffs[0], diffs[ROUNDS - 1]])
	quit(0)

func _measure(vp: Viewport, meshes: Array[MeshInstance3D], rooms: Array[int], on: bool) -> float:
	for i in meshes.size():
		meshes[i].set_instance_shader_parameter("room", rooms[i] if on else -1)
	for i in 10:
		await process_frame  # settle
	var sum := 0.0
	var n := 0
	for i in FRAMES:
		await process_frame
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		if g > 0.0 and g < 1000.0:
			sum += g
			n += 1
	return sum / maxf(float(n), 1.0)
