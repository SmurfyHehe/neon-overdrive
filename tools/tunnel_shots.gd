extends SceneTree

# Night screenshots and parked frame rate at a place on the loop (TN1, the
# tunnel under Downtown). Boots the game through the test harness (its own
# settings file, not yours) on the Low graphics tier with no traffic, the
# clock pinned, the player parked TUNNEL_SHOT_S metres round the loop; saves
# the chase view, then counts frames with V-Sync off. Needs the real renderer.
#
#   TUNNEL_SHOT_S=<metres> [NEON_SHOT=<path.png>] [TUNNEL_SHOT_STREET=1] [NEON_TUNNEL=0]
#     <godot> --path . -s res://tools/tunnel_shots.gd
#
# TUNNEL_SHOT_STREET=1 also saves <path>_street.png: the trench seen from the
# pavement beside it, looking at the mouth. NEON_TUNNEL=0 is the same place
# without the tunnel, to compare frame rates. The tunnel is at 4250-4550 m.

const TunnelKit := preload("res://scripts/world/tunnel_kit.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")

const SETTLE_FRAMES := 150
const FPS_FRAMES := 400

var game: Node

func _initialize() -> void:
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "22:30")
	if OS.get_environment("NEON_SEED") == "":
		OS.set_environment("NEON_SEED", "777")
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_ROAD", "0")
	OS.set_environment("NEON_POLICE", "0")
	var s := OS.get_environment("TUNNEL_SHOT_S")
	OS.set_environment("NEON_START_S", s if s.is_valid_float() else "4400")
	game = (preload("res://tests/traffic/traffic_harness.gd") as GDScript).boot(self, 0, 150.0, 777)
	_run.call_deferred()

func _run() -> void:
	GraphicsSettings.set_preset("low")
	TrafficSettings.set_car_count(0)
	GraphicsSettings.apply(self)
	for i in SETTLE_FRAMES:
		await process_frame
	var path := OS.get_environment("NEON_SHOT")
	if path == "":
		path = "user://tunnel_%s.png" % OS.get_environment("NEON_START_S")
	var err := root.get_viewport().get_texture().get_image().save_png(path)
	var player: Node3D = game.get("player")
	var u := RoadFrame.unroll(player.global_position)
	var s := RoadMap.wrap_s(RoadFrame.s_at(u.z))
	print("tunnel_shots: %s at %.0f m (tunnel %s, %.0f m inside) -> %s" % [error_string(err), s,
		"live" if RoadMap.tunnel_live else "off", RoadMap.tunnel_depth(s), ProjectSettings.globalize_path(path)])
	if OS.get_environment("TUNNEL_SHOT_DEBUG") == "1":
		# what the chunk under the car is drawing
		for entry in game.get("chunk_pool"):
			if int(entry.index) != floori(RoadFrame.s_at(u.z) / 50.0):
				continue
			for c in (entry.root as Node3D).get_children():
				if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh.visible_instance_count != 0 and (c as Node3D).visible:
					print("  mm %s x%d" % [c.name, (c as MultiMeshInstance3D).multimesh.visible_instance_count])
				elif c is MeshInstance3D and (c as Node3D).visible and (c as MeshInstance3D).mesh != null:
					var bb := (c as MeshInstance3D).get_aabb()
					print("  mesh %s x %.1f..%.1f y %.1f..%.1f" % [c.name, bb.position.x, bb.end.x, bb.position.y, bb.end.y])
	if OS.get_environment("TUNNEL_SHOT_DEBUG") == "2":
		# everything drawn above head height within 30 m of the car
		var stack: Array = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
				var g := n as GeometryInstance3D
				var bb := g.global_transform * g.get_aabb()
				var near := bb.grow(30.0).has_point(player.global_position)
				if near and bb.end.y > player.global_position.y + 3.0 and bb.size.length() < 200.0:
					print("  high %s size %s at %s" % [n.get_path(), bb.size, bb.get_center() - player.global_position])
	if OS.get_environment("TUNNEL_SHOT_STREET") == "1":
		var chunk := floori(RoadFrame.s_at(u.z) / 50.0)
		var dep := TunnelKit.depths(chunk)
		var here: float = dep[clampi(int(RoadFrame.s_at(u.z) - float(chunk) * 50.0), 0, 50)] if not dep.is_empty() else 0.0
		var cam := Camera3D.new()
		cam.fov = 70.0
		root.add_child(cam)
		cam.global_position = RoadFrame.roll(Vector3(17.5, here + 1.7, u.z))
		cam.look_at(RoadFrame.roll(Vector3(0.0, here + 1.0, u.z - 55.0)), Vector3.UP)
		cam.make_current()
		for i in 30:
			await process_frame
		var street_path := path.get_basename() + "_street.png"
		root.get_viewport().get_texture().get_image().save_png(street_path)
		print("tunnel_shots: street side -> %s" % ProjectSettings.globalize_path(street_path))
		cam.queue_free()
		(game.get("camera") as Camera3D).make_current()
		for i in 10:
			await process_frame
	# Parked frame rate, uncapped.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in 60:
		await process_frame
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in FPS_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var avg := total / float(times.size())
	var slow := times[int(float(times.size()) * 0.99)]
	print("tunnel_shots: fps at %.0f m, tunnel %s, Low: avg %.1f (%.2f ms), 1%% low %.1f (%.2f ms), draw calls %d, objects %d" % [
		s, "live" if RoadMap.tunnel_live else "off", 1000.0 / avg, avg, 1000.0 / slow, slow,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	quit(0 if err == OK else 1)
